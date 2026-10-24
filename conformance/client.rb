#!/usr/bin/env ruby
# frozen_string_literal: true

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

# Client-under-test for the Connect conformance runner (--mode client). Reads length-prefixed
# ClientCompatRequests from stdin, issues each RPC through the generated ConformanceServiceClient,
# and writes a length-prefixed ClientCompatResponse per request to stdout.
#
# RPCs run on a pool of threads sharing httpx sessions, so the suite also exercises clients
# used concurrently. Responses may be written in any order; the runner matches them by test name.

$LOAD_PATH.unshift(File.expand_path("gen", __dir__))

require "connect_rpc_httpx"
require "connectrpc/conformance/v1/client_compat_pb"
require "connectrpc/conformance/v1/service_connect"

V1 = Connectrpc::Conformance::V1
SERVICE = V1::ConformanceServiceClient
WORKERS = 8

# The RPCs of the service, with the request type each expects inside its Any.
METHODS = {
  "Unary" => [SERVICE::UNARY, V1::UnaryRequest],
  "IdempotentUnary" => [SERVICE::IDEMPOTENT_UNARY, V1::IdempotentUnaryRequest],
  "Unimplemented" => [SERVICE::UNIMPLEMENTED, V1::UnimplementedRequest],
  "ServerStream" => [SERVICE::SERVER_STREAM, V1::ServerStreamRequest],
  "ClientStream" => [SERVICE::CLIENT_STREAM, V1::ClientStreamRequest],
  "BidiStream" => [SERVICE::BIDI_STREAM, V1::BidiStreamRequest],
}.freeze

def read_message(io, message_class)
  prefix = io.read(4) or return
  message_class.decode(io.read(prefix.unpack1("N")))
end

def write_message(io, message)
  bytes = message.class.encode(message)
  io.write([bytes.bytesize].pack("N"), bytes)
  io.flush
end

def headers_from(request)
  request.request_headers.to_h { |header| [header.name, header.value.to_a] }
end

def headers_to(metadata)
  metadata.map { |name, values| V1::Header.new(name:, value: values) }
end

# One httpx session per transport configuration, shared by every RPC that uses it.
class Sessions
  def initialize
    @sessions = {}
    @lock = Mutex.new
  end

  def for(request)
    creds = request.client_tls_creds
    key = [request.http_version, request.server_tls_cert, creds&.cert, creds&.key]
    @lock.synchronize { @sessions[key] ||= build(request) }
  end

  private def build(request)
    http2 = request.http_version == :HTTP_VERSION_2
    if request.server_tls_cert.empty?
      # Cleartext HTTP/2 can only be spoken with prior knowledge.
      return HTTPX.plugin(:persistent).with(fallback_protocol: http2 ? "h2" : "http/1.1")
    end

    store = OpenSSL::X509::Store.new
    store.add_cert(OpenSSL::X509::Certificate.new(request.server_tls_cert))
    ssl = {cert_store: store, verify_mode: OpenSSL::SSL::VERIFY_PEER, alpn_protocols: [http2 ? "h2" : "http/1.1"]}
    if (creds = request.client_tls_creds)
      ssl[:cert] = OpenSSL::X509::Certificate.new(creds.cert)
      ssl[:key] = OpenSSL::PKey.read(creds.key)
    end
    HTTPX.plugin(:persistent).with(ssl:)
  end
end

def run_rpc(request, sessions)
  raise "unsupported protocol #{request.protocol}" unless request.protocol == :PROTOCOL_CONNECT
  raise "unsupported service #{request.service}" unless request.service == SERVICE::SERVICE_NAME

  # Read by name, because a "method" accessor would shadow Object#method.
  method, request_class = METHODS.fetch(request["method"]) { raise "unsupported method #{request["method"]}" }
  messages = request.request_messages.map { |any| any.unpack(request_class) or raise "request is not a #{request_class}" }

  scheme = request.server_tls_cert.empty? ? "http" : "https"
  client = SERVICE.new(
    "#{scheme}://#{request.host}:#{request.port}",
    codec: request.codec == :CODEC_JSON ? :json : :proto,
    http: sessions.for(request),
    http_get: request.use_get_http_method,
  )
  options = {headers: headers_from(request), timeout: request.has_timeout_ms? ? request.timeout_ms / 1000.0 : nil}

  case method.stream_type
  when :unary
    single_result { client.call_unary(method, messages.first, **options) }
  when :client_stream
    single_result { client.call_client_stream(method, delayed(messages, request.request_delay_ms), **options) }
  when :server_stream
    stream_result(client.call_server_stream(method, messages.first, **options))
  when :bidi_stream
    stream_result(client.call_bidi_stream(method, delayed(messages, request.request_delay_ms), **options))
  end
end

# The suite asks for a pause before each request message of a stream.
def delayed(messages, delay_ms)
  return messages unless delay_ms.positive?

  Enumerator.new do |out|
    messages.each do |message|
      sleep(delay_ms / 1000.0)
      out << message
    end
  end
end

def single_result
  response = yield
  V1::ClientResponseResult.new(
    response_headers: headers_to(response.headers),
    payloads: [response.message.payload || V1::ConformancePayload.new],
    response_trailers: headers_to(response.trailers),
  )
rescue ConnectRpcHttpx::Error => e
  error_result(e, e.headers)
end

def stream_result(stream)
  payloads = []
  stream.each { |message| payloads << (message.payload || V1::ConformancePayload.new) }
  V1::ClientResponseResult.new(
    response_headers: headers_to(stream.headers || {}),
    payloads:,
    response_trailers: headers_to(stream.trailers || {}),
  )
rescue ConnectRpcHttpx::Error => e
  error_result(e, stream.headers || e.headers, payloads)
end

def error_result(error, headers, payloads = [])
  V1::ClientResponseResult.new(
    response_headers: headers_to(headers),
    payloads:,
    error: V1::Error.new(code: :"CODE_#{error.code.upcase}", message: error.message, details: error.details),
    response_trailers: headers_to(error.trailers),
  )
end

def handle(request, sessions)
  V1::ClientCompatResponse.new(test_name: request.test_name, response: run_rpc(request, sessions))
rescue => e
  V1::ClientCompatResponse.new(
    test_name: request.test_name,
    error: V1::ClientErrorResult.new(message: "#{e.class}: #{e.message}"),
  )
end

$stdin.binmode
$stdout.binmode
sessions = Sessions.new
output = Mutex.new
queue = Thread::Queue.new
workers = Array.new(WORKERS) do
  Thread.new do
    while (request = queue.pop)
      response = handle(request, sessions)
      output.synchronize { write_message($stdout, response) }
    end
  end
end

while (request = read_message($stdin, V1::ClientCompatRequest))
  queue << request
end
queue.close
workers.each(&:join)
