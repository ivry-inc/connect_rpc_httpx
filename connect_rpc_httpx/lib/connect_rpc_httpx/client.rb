# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

require "base64"
require "uri"
require "httpx"

module ConnectRpcHttpx
  # Base class of generated Connect clients, issuing RPCs over an httpx session.
  #
  # A client is frozen once built and can be shared between threads. Its httpx session pools
  # connections per session, and that pool is thread-safe.
  #
  #   client = Acme::Greet::V1::GreetServiceClient.new("https://api.example.com")
  #   client.greet(Acme::Greet::V1::GreetRequest.new(name: "Ruby")).greeting
  class Client
    USER_AGENT = "connect-ruby-httpx/#{VERSION}".freeze #: String

    # connect-timeout-ms allows at most 10 digits.
    MAX_TIMEOUT_MS = 9_999_999_999 #: Integer

    # Decoded transparently by httpx, so a response compressed with these reads as plain.
    RESPONSE_ENCODINGS = ["identity", "gzip", "deflate"].freeze #: Array[String]

    # The server's base URL, without a trailing slash. RPC paths are appended to it.
    attr_reader :base_url #: String

    attr_reader :codec #: Codec::_Codec

    # The httpx session RPCs are sent through.
    attr_reader :http #: HTTPX::Session

    # Request headers sent with every RPC, with lowercase keys.
    attr_reader :headers #: Hash[String, Array[String]]

    # The default deadline of an RPC, in seconds.
    attr_reader :timeout #: seconds?

    # Whether RPCs declared free of side effects are sent with Connect GET.
    attr_reader :http_get #: bool

    # @rbs @stream_http: HTTPX::Session

    # Builds a client for the server at +base_url+.
    #
    # +codec+ is :proto or :json. +http+ is the httpx session to send through, and defaults to
    # a persistent one owned by this client. +headers+ and +timeout+ (seconds) apply to every
    # RPC unless a call overrides them. With +http_get+, RPCs whose idempotency_level is
    # NO_SIDE_EFFECTS use HTTP GET, which caches and proxies can serve.
    #
    #: (String base_url, ?codec: Symbol, ?http: HTTPX::Session?, ?headers: Hash[String, String | Array[String]], ?timeout: seconds?, ?http_get: bool) -> void
    def initialize(base_url, codec: :proto, http: nil, headers: {}, timeout: nil, http_get: false)
      @base_url = base_url.delete_suffix("/").freeze
      @codec = Codec.fetch(codec)
      @http = http || HTTPX.plugin(:persistent)
      @stream_http = @http.plugin(:stream)
      @headers = normalize_headers(headers)
      @timeout = timeout
      @http_get = http_get
      freeze
    end

    # Issues a unary RPC and returns its response message with the response metadata.
    #
    # +headers+ are merged over the client's, replacing headers of the same name. +timeout+
    # (seconds) replaces the client's deadline, and nil sends no deadline at all.
    #
    # Raises ConnectRpcHttpx::Error when the RPC fails, including transport failures.
    #
    #: [I, O] (MethodDescriptor[I, O] method, I request, ?headers: Hash[String, String | Array[String]], ?timeout: seconds?) -> UnaryResponse[O]
    def call_unary(method, request, headers: {}, timeout: self.timeout)
      check_stream_type(method, :unary)
      check_deadline(timeout)

      body = codec.encode(method.input, request)
      request_headers = request_headers(headers, timeout)

      response = if http_get && method.no_side_effects?
        get(method, body, request_headers, timeout)
      else
        post(method, body, request_headers, timeout)
      end
      read_unary_response(method, response, timeout)
    end

    # Issues a server-streaming RPC. With a block, yields each response message as it arrives;
    # without one, returns the stream unread, to be iterated later. Either way the stream is
    # returned, for its headers and trailers.
    #
    # Raises ConnectRpcHttpx::Error when the RPC fails, during iteration.
    #
    #: [I, O] (MethodDescriptor[I, O] method, I request, ?headers: Hash[String, String | Array[String]], ?timeout: seconds?) ?{ (O message) -> void } -> ResponseStream[O]
    def call_server_stream(method, request, headers: {}, timeout: self.timeout, &block)
      check_stream_type(method, :server_stream)
      stream_response(method, [request], headers, timeout, &block)
    end

    # Issues a client-streaming RPC, sending each message +requests+ enumerates, and returns the
    # single response message with the response metadata. +requests+ may be any Enumerable,
    # including a lazy Enumerator; its messages are sent as they are produced.
    #
    # Raises ConnectRpcHttpx::Error when the RPC fails.
    #
    #: [I, O] (MethodDescriptor[I, O] method, Enumerable[I] requests, ?headers: Hash[String, String | Array[String]], ?timeout: seconds?) -> UnaryResponse[O]
    def call_client_stream(method, requests, headers: {}, timeout: self.timeout)
      check_stream_type(method, :client_stream)
      check_deadline(timeout)

      stream = ResponseStream.new(stream_call(method, requests, headers, timeout))
      messages = stream.to_a
      response_headers = stream.headers || {}
      trailers = stream.trailers || {}
      unless messages.size == 1
        raise Error.new(:unimplemented, "client stream got #{messages.size} response messages, not 1", headers: response_headers, trailers:)
      end

      UnaryResponse.new(message: messages.fetch(0), headers: response_headers, trailers:)
    end

    # Issues a bidirectional-streaming RPC in half-duplex: every message +requests+ enumerates is
    # sent, then the responses are read as #call_server_stream reads them.
    #
    #: [I, O] (MethodDescriptor[I, O] method, Enumerable[I] requests, ?headers: Hash[String, String | Array[String]], ?timeout: seconds?) ?{ (O message) -> void } -> ResponseStream[O]
    def call_bidi_stream(method, requests, headers: {}, timeout: self.timeout, &block)
      check_stream_type(method, :bidi_stream)
      stream_response(method, requests, headers, timeout, &block)
    end

    #: [I, O] (MethodDescriptor[I, O] method, Enumerable[I] requests, Hash[String, String | Array[String]] headers, seconds? timeout) ?{ (O message) -> void } -> ResponseStream[O]
    private def stream_response(method, requests, headers, timeout, &block)
      check_deadline(timeout)
      stream = ResponseStream.new(stream_call(method, requests, headers, timeout))
      block ? stream.each(&block) : stream
    end

    #: [I, O] (MethodDescriptor[I, O] method, Enumerable[I] requests, Hash[String, String | Array[String]] headers, seconds? timeout) -> StreamCall[I, O]
    private def stream_call(method, requests, headers, timeout)
      request_headers = request_headers(headers, timeout)
      request_headers["connect-protocol-version"] = ["1"]
      request_headers["content-type"] = ["application/connect+#{codec.name}"]
      StreamCall.new(
        http: @stream_http,
        url: "#{base_url}#{method.path}",
        headers: request_headers,
        codec:,
        method:,
        requests:,
        timeout:,
      )
    end

    #: (MethodDescriptor[untyped, untyped] method, Symbol stream_type) -> void
    private def check_stream_type(method, stream_type)
      return if method.stream_type == stream_type

      raise ArgumentError, "#{method.path} is a #{method.stream_type} RPC, not #{stream_type}"
    end

    #: (seconds? timeout) -> void
    private def check_deadline(timeout)
      raise Error.new(:deadline_exceeded, "deadline exceeded before sending") if timeout && timeout <= 0
    end

    # The client's headers with the call's merged over them, plus the headers every RPC sends.
    #: (Hash[String, String | Array[String]] headers, seconds? timeout) -> Hash[String, Array[String]]
    private def request_headers(headers, timeout)
      request_headers = self.headers.merge(normalize_headers(headers))
      request_headers["user-agent"] ||= [USER_AGENT]
      request_headers["connect-timeout-ms"] = [timeout_ms(timeout).to_s] if timeout
      request_headers
    end

    #: [I, O] (MethodDescriptor[I, O] method, String body, Hash[String, Array[String]] headers, seconds? timeout) -> HTTPX::response
    private def post(method, body, headers, timeout)
      headers["connect-protocol-version"] = ["1"]
      headers["content-type"] = [codec.content_type]
      http.request("POST", "#{base_url}#{method.path}", headers:, body:, **timeout_options(timeout))
    end

    # The query parameters keep the order the Connect conformance suite expects, which also keeps
    # the URL stable for caches.
    #: [I, O] (MethodDescriptor[I, O] method, String body, Hash[String, Array[String]] headers, seconds? timeout) -> HTTPX::response
    private def get(method, body, headers, timeout)
      query = URI.encode_www_form(
        connect: "v1",
        base64: "1",
        encoding: codec.name,
        message: Base64.urlsafe_encode64(body, padding: false),
      )
      http.request("GET", "#{base_url}#{method.path}?#{query}", headers:, **timeout_options(timeout))
    end

    #: (seconds? timeout) -> Hash[Symbol, untyped]
    private def timeout_options(timeout)
      timeout ? {timeout: {total_request_timeout: timeout}} : {}
    end

    #: [I, O] (MethodDescriptor[I, O] method, HTTPX::response response, seconds? timeout) -> UnaryResponse[O]
    private def read_unary_response(method, response, timeout)
      if response.is_a?(HTTPX::ErrorResponse)
        error = response.error
        raise Error.new(Error.transport_code(error, timeout:), "request to #{method.path} failed"), cause: error
      end

      headers, trailers = split_metadata(response.headers)
      body = response.body.to_s.b
      content_type = response.headers["content-type"]
      unless response.status == 200
        raise Error.from_unary_response(status: response.status, content_type:, body:, headers:, trailers:)
      end

      check_response_encoding(response.headers["content-encoding"], headers, trailers)
      check_response_content_type(content_type, headers, trailers)
      message = begin
        codec.decode(method.output, body)
      rescue Google::Protobuf::ParseError
        raise Error.new(:internal, "unmarshal response into #{method.name} output failed", headers:, trailers:)
      end
      UnaryResponse.new(message:, headers:, trailers:)
    end

    #: (String? encoding, Hash[String, Array[String]] headers, Hash[String, Array[String]] trailers) -> void
    private def check_response_encoding(encoding, headers, trailers)
      return if encoding.nil? || RESPONSE_ENCODINGS.include?(encoding.strip.downcase)

      raise Error.new(:internal, "unsupported response content-encoding: #{encoding}", headers:, trailers:)
    end

    # A body that is not a Connect message at all is :unknown; a Connect message in another
    # codec than requested is :internal.
    #: (String? content_type, Hash[String, Array[String]] headers, Hash[String, Array[String]] trailers) -> void
    private def check_response_content_type(content_type, headers, trailers)
      media_type = Codec.media_type(content_type)
      return if media_type == codec.content_type

      code = media_type&.start_with?("application/") ? :internal : :unknown
      raise Error.new(code, "unexpected response content-type: #{content_type.inspect}", headers:, trailers:)
    end

    # Connect unary responses carry trailers as headers with a "trailer-" prefix.
    #: (HTTPX::Headers response_headers) -> [Hash[String, Array[String]], Hash[String, Array[String]]]
    private def split_metadata(response_headers)
      trailers, headers = Metadata.from_httpx(response_headers).partition { |name, _| name.start_with?("trailer-") }
      [headers.to_h, trailers.to_h { |name, values| [name.delete_prefix("trailer-"), values] }]
    end

    #: (seconds timeout) -> Integer
    private def timeout_ms(timeout)
      (timeout * 1000).ceil.clamp(1, MAX_TIMEOUT_MS)
    end

    #: (Hash[String, String | Array[String]] headers) -> Hash[String, Array[String]]
    private def normalize_headers(headers)
      headers.to_h do |name, value|
        values = value.is_a?(Array) ? value : [value]
        [name.downcase.freeze, values.map { |v| v.dup.freeze }.freeze]
      end.freeze
    end
  end
end
