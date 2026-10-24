# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

require "json"
require "httpx"

module ConnectRpcHttpx
  # One streaming RPC over the Connect streaming protocol: enveloped request messages out, then
  # enveloped response messages and an end-of-stream message back. Client builds these; it is not
  # meant to be used directly.
  #
  # @rbs generic I -- the request message
  # @rbs generic O -- the response message
  class StreamCall
    # httpx closes a connection idle longer than its operation timeout, and rejects infinity.
    # A stream may legitimately stay silent for long, so a year stands in for no limit.
    IDLE_TIMEOUT = 31_536_000 #: Integer

    # @rbs @http: HTTPX::Session
    # @rbs @url: String
    # @rbs @headers: metadata
    # @rbs @codec: Codec::_Codec
    # @rbs @input: _MessageClass[I]
    # @rbs @output: _MessageClass[O]
    # @rbs @requests: Enumerable[I]
    # @rbs @timeout: seconds?
    # @rbs @reader: Envelope::Reader
    # @rbs @response_headers: metadata?
    # @rbs @error_body: String?
    # @rbs @end_message: String?
    # @rbs @caller_error: StandardError?

    #: (http: HTTPX::Session, url: String, headers: metadata, codec: Codec::_Codec, method: MethodDescriptor[I, O], requests: Enumerable[I], timeout: seconds?) -> void
    def initialize(http:, url:, headers:, codec:, method:, requests:, timeout:)
      @http = http
      @url = url
      @headers = headers
      @codec = codec
      @input = method.input
      @output = method.output
      @requests = requests
      @timeout = timeout
      @reader = Envelope::Reader.new
      @response_headers = nil
      @error_body = nil
      @end_message = nil
      @caller_error = nil
    end

    # Sends the request messages, reports the response headers and each response message, and
    # returns the trailers. Raises Error when the RPC fails.
    #
    # Exceptions from the caller's code (the request Enumerable, +on_headers+, +on_message+)
    # propagate as they are, and leaving early cancels the RPC.
    #
    #: (^(metadata) -> void on_headers, ^(O) -> void on_message) -> metadata
    def run(on_headers, on_message)
      response = @http.request(build_request)
      finished = false
      begin
        response.each { |chunk| receive(response, chunk, on_headers, on_message) }
        finished = true
      rescue HTTPX::HTTPError => e
        raise_original(e)
        # A status of 400 or above; #finish reads the error from the body collected so far.
        finished = true
      rescue StandardError => e
        raise_original(e)
        finished = true
        raise Error.new(Error.transport_code(e, timeout: @timeout), "stream to #{@url} failed", headers: @response_headers || {}), cause: e
      ensure
        # An abandoned response would otherwise be read by the next request on its connection.
        response.request.handle_error(HTTPX::Error.new("stream abandoned")) unless finished
      end
      finish(response, on_headers)
    end

    #: () -> HTTPX::Request
    private def build_request
      request = @http.build_request("POST", @url, {headers: @headers, body: request_body, stream: true, timeout:})
      # httpx 1.9 writes the CRLF that ends a chunked HTTP/1.1 body only for a request with
      # trailers, so the server would wait for the rest of the body. Empty trailers supply it.
      request.trailers
      request.on(:trailers) { nil }
      request
    end

    #: () -> Hash[Symbol, untyped]
    private def timeout
      @timeout ? {total_request_timeout: @timeout, operation_timeout: IDLE_TIMEOUT} : {operation_timeout: IDLE_TIMEOUT}
    end

    #: () -> Enumerator[String, void]
    private def request_body
      Enumerator.new do |body|
        callback { @requests.each { |message| body << Envelope.encode(@codec.encode(@input, message)) } }
      end
    end

    #: (untyped response, String chunk, ^(metadata) -> void on_headers, ^(O) -> void on_message) -> void
    private def receive(response, chunk, on_headers, on_message)
      start(response, on_headers) unless @response_headers
      if (error_body = @error_body)
        error_body << chunk
        return
      end

      @reader.push(chunk) do |flags, data|
        raise protocol_error("received a message after the end of the stream") if @end_message
        raise protocol_error("received a compressed message without a negotiated encoding") if flags.anybits?(Envelope::COMPRESSED)

        if flags.anybits?(Envelope::END_STREAM)
          @end_message = data
        else
          message = decode(data)
          callback { on_message.call(message) }
        end
      end
    end

    # Checks the response once its status and headers have arrived, before any body is read.
    #: (untyped response, ^(metadata) -> void on_headers) -> void
    private def start(response, on_headers)
      headers = Metadata.from_httpx(response.headers)
      @response_headers = headers
      return @error_body = "".b unless response.status == 200

      content_type = response.headers["content-type"]
      media_type = Codec.media_type(content_type)
      unless media_type == "application/connect+#{@codec.name}"
        code = media_type&.start_with?("application/connect+") ? :internal : :unknown
        raise Error.new(code, "unexpected response content-type: #{content_type.inspect}", headers:)
      end

      callback { on_headers.call(headers) }
    end

    #: (untyped response, ^(metadata) -> void on_headers) -> metadata
    private def finish(response, on_headers)
      start(response, on_headers) unless @response_headers
      headers = @response_headers || {}
      if (error_body = @error_body)
        raise Error.from_unary_response(
          status: response.status, content_type: response.headers["content-type"], body: error_body, headers:, trailers: {},
        )
      end
      raise protocol_error("the stream ended inside a message") if @reader.partial?

      end_message = @end_message or raise protocol_error("the stream ended without an end-of-stream message")
      wire = parse_end_message(end_message)
      trailers = parse_trailers(wire["metadata"])
      if (error = wire["error"])
        raise protocol_error("malformed end-of-stream error") unless error.is_a?(Hash)

        raise Error.from_wire(error, fallback_code: :unknown, headers:, trailers:)
      end
      trailers
    end

    #: (String data) -> Hash[String, untyped]
    private def parse_end_message(data)
      wire = JSON.parse(data)
      raise protocol_error("malformed end-of-stream message") unless wire.is_a?(Hash)

      wire
    rescue JSON::ParserError
      raise protocol_error("malformed end-of-stream message")
    end

    #: (untyped metadata) -> metadata
    private def parse_trailers(metadata)
      return {} if metadata.nil?
      raise protocol_error("malformed end-of-stream metadata") unless metadata.is_a?(Hash)

      metadata.to_h do |name, values|
        raise protocol_error("malformed end-of-stream metadata") unless values.is_a?(Array) && values.all?(String)

        [name.to_s.downcase, values]
      end
    end

    #: (String data) -> O
    private def decode(data)
      @codec.decode(@output, data)
    rescue Google::Protobuf::ParseError
      raise protocol_error("unmarshal of a response message failed")
    end

    #: (String message) -> Error
    private def protocol_error(message)
      Error.new(:internal, "protocol error: #{message}", headers: @response_headers || {})
    end

    # Re-raises an exception this class or the caller's code raised. The http-2 gem wraps an
    # exception raised in its callbacks, keeping the original as the cause.
    #: (StandardError error) -> void
    private def raise_original(error)
      current = error #: Exception?
      while current
        raise current if current.equal?(@caller_error) || current.is_a?(Error)

        current = current.cause
      end
    end

    # Runs the caller's code, remembering an exception from it so #run propagates it untouched.
    #: [T] () { () -> T } -> T
    private def callback
      yield
    rescue StandardError => e
      @caller_error = e
      raise
    end
  end
end
