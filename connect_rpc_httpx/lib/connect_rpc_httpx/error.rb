# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

require "base64"
require "json"
require "httpx"
require "google/protobuf/well_known_types"

module ConnectRpcHttpx
  # A failed RPC: the server's Connect error, or a client-side failure expressed as one.
  #
  # Response headers and trailers are kept when the server sent any, so error metadata is
  # readable the same way as a successful response's.
  class Error < StandardError
    attr_reader :code #: Symbol

    # Error details, each a google.protobuf.Any. Unpack one with +Any#unpack+.
    attr_reader :details #: Array[Google::Protobuf::Any]

    attr_reader :headers #: Hash[String, Array[String]]
    attr_reader :trailers #: Hash[String, Array[String]]

    #: (Symbol code, ?String? message, ?details: Array[Google::Protobuf::Any], ?headers: Hash[String, Array[String]], ?trailers: Hash[String, Array[String]]) -> void
    def initialize(code, message = nil, details: [], headers: {}, trailers: {})
      raise ArgumentError, "unknown Connect error code: #{code.inspect}" unless Code.valid?(code)

      @code = code
      @details = details
      @headers = headers
      @trailers = trailers
      super(message || code.to_s)
    end

    # Builds the error a unary response with a non-200 status stands for. A body that is not a
    # Connect error falls back to the protocol's HTTP status mapping.
    #: (status: Integer, content_type: String?, body: String, headers: Hash[String, Array[String]], trailers: Hash[String, Array[String]]) -> Error
    def self.from_unary_response(status:, content_type:, body:, headers:, trailers:)
      wire = parse_wire_error(body) if Codec::Json.content_type?(content_type)
      return new(Code.from_http_status(status), "HTTP status #{status}", headers:, trailers:) unless wire

      from_wire(wire, fallback_code: Code.from_http_status(status), headers:, trailers:)
    end

    # Builds an error from its Connect JSON form, as a unary error body or the "error" member of a
    # stream's end message carries it. +fallback_code+ stands in for a missing or unknown code.
    #: (Hash[String, untyped] wire, fallback_code: Symbol, headers: Hash[String, Array[String]], trailers: Hash[String, Array[String]]) -> Error
    def self.from_wire(wire, fallback_code:, headers:, trailers:)
      code = wire["code"].is_a?(String) ? wire["code"].to_sym : nil
      code = fallback_code unless code && Code.valid?(code)
      message = wire["message"].is_a?(String) ? wire["message"] : ""
      new(code, message, details: parse_details(wire["details"]), headers:, trailers:)
    end

    # The code for an RPC that failed in transport. A response that is not valid HTTP came from the
    # server, so it is :unknown rather than a failure to reach the server.
    #: (StandardError error, timeout: seconds?) -> Symbol
    def self.transport_code(error, timeout:)
      case error
      when HTTPX::TimeoutError then timeout ? :deadline_exceeded : :unavailable
      when HTTPX::Parser::Error then :unknown
      else :unavailable
      end
    end

    #: (String body) -> Hash[String, untyped]?
    def self.parse_wire_error(body)
      wire = JSON.parse(body)
      wire if wire.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    # Malformed entries are skipped rather than failing the whole error.
    #: (untyped details) -> Array[Google::Protobuf::Any]
    def self.parse_details(details)
      return [] unless details.is_a?(Array)

      details.filter_map do |detail|
        next unless detail.is_a?(Hash) && detail["type"].is_a?(String) && detail["value"].is_a?(String)

        Google::Protobuf::Any.new(type_url: "type.googleapis.com/#{detail["type"]}", value: decode_base64(detail["value"]))
      rescue ArgumentError
        nil
      end
    end

    # Connect sends unpadded base64, and both alphabets are accepted in the wild.
    #: (String value) -> String
    def self.decode_base64(value)
      padded = value.tr("-_", "+/")
      padded += "=" * (-padded.length % 4)
      Base64.strict_decode64(padded)
    end

    private_class_method :parse_wire_error, :parse_details, :decode_base64
  end
end
