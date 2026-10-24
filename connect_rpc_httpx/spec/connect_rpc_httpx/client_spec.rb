# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe(ConnectRpcHttpx::Client) do
  let(:base_url) { "http://connect.test/api/" }
  let(:method_descriptor) do
    ConnectRpcHttpx::MethodDescriptor.new(
      service: "test.v1.EchoService",
      name: "Echo",
      input: TestMessages::EchoRequest,
      output: TestMessages::EchoResponse,
    )
  end
  let(:client) { described_class.new(base_url) }
  let(:url) { "http://connect.test/api/test.v1.EchoService/Echo" }
  let(:request) { TestMessages::EchoRequest.new(text: "hello") }

  def proto_response(value, headers: {})
    {
      status: 200,
      headers: {"content-type" => "application/proto"}.merge(headers),
      body: TestMessages::EchoResponse.encode(TestMessages::EchoResponse.new(count: value)),
    }
  end

  def error_response(status, body, content_type: "application/json")
    {status:, headers: {"content-type" => content_type}, body:}
  end

  it "is frozen" do
    expect(client).to be_frozen
  end

  describe "#call_unary" do
    it "POSTs the encoded request and decodes the response" do
      stub = stub_request(:post, url)
        .with(
          body: TestMessages::EchoRequest.encode(request),
          headers: {
            "content-type" => "application/proto",
            "connect-protocol-version" => "1",
            "user-agent" => ConnectRpcHttpx::Client::USER_AGENT,
          },
        )
        .to_return(proto_response(42))

      response = client.call_unary(method_descriptor, request)

      expect(stub).to have_been_requested
      expect(response.message).to eq(TestMessages::EchoResponse.new(count: 42))
    end

    it "separates trailer- prefixed headers into trailers" do
      stub_request(:post, url).to_return(proto_response(1, headers: {"x-header" => "a", "trailer-x-trailer" => "b"}))

      response = client.call_unary(method_descriptor, request)

      expect(response.headers).to include("x-header" => ["a"])
      expect(response.headers).not_to have_key("trailer-x-trailer")
      expect(response.trailers).to eq("x-trailer" => ["b"])
    end

    it "sends the client's headers merged with the call's" do
      client = described_class.new(base_url, headers: {"X-Client" => "c", "x-both" => "client"})
      stub = stub_request(:post, url)
        .with(headers: {"x-client" => "c", "x-both" => "call", "x-call" => "1"})
        .to_return(proto_response(1))

      client.call_unary(method_descriptor, request, headers: {"x-both" => "call", "x-call" => "1"})

      expect(stub).to have_been_requested
    end

    it "sends through the given httpx session and its plugins" do
      http = HTTPX.plugin(:persistent).plugin(:auth).bearer_auth("TOKEN")
      client = described_class.new(base_url, http:)
      stub = stub_request(:post, url).with(headers: {"authorization" => "Bearer TOKEN"}).to_return(proto_response(1))

      client.call_unary(method_descriptor, request)

      expect(stub).to have_been_requested
    end

    it "sends the deadline as connect-timeout-ms" do
      stub = stub_request(:post, url).with(headers: {"connect-timeout-ms" => "1500"}).to_return(proto_response(1))

      client.call_unary(method_descriptor, request, timeout: 1.5)

      expect(stub).to have_been_requested
    end

    it "fails an expired deadline without sending" do
      expect { client.call_unary(method_descriptor, request, timeout: 0) }
        .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:deadline_exceeded) }
      expect(a_request(:post, url)).not_to have_been_made
    end

    context "with the JSON codec" do
      let(:client) { described_class.new(base_url, codec: :json) }

      it "exchanges JSON bodies" do
        stub = stub_request(:post, url)
          .with(body: '{"text":"hello"}', headers: {"content-type" => "application/json"})
          .to_return(status: 200, headers: {"content-type" => "application/json; charset=utf-8"}, body: '{"count":"7","unknown":1}')

        expect(client.call_unary(method_descriptor, request).message.count).to eq(7)
        expect(stub).to have_been_requested
      end
    end

    context "with http_get" do
      let(:client) { described_class.new(base_url, http_get: true) }
      let(:method_descriptor) do
        ConnectRpcHttpx::MethodDescriptor.new(
          service: "test.v1.EchoService",
          name: "Echo",
          input: TestMessages::EchoRequest,
          output: TestMessages::EchoResponse,
          idempotency: :no_side_effects,
        )
      end

      it "sends a side-effect-free RPC as a Connect GET" do
        message = Base64.urlsafe_encode64(TestMessages::EchoRequest.encode(request), padding: false)
        stub = stub_request(:get, "#{url}?connect=v1&base64=1&encoding=proto&message=#{message}")
          .to_return(proto_response(3))

        expect(client.call_unary(method_descriptor, request).message.count).to eq(3)
        expect(stub).to have_been_requested
      end
    end

    context "when the server answers with a Connect error" do
      it "raises it with its code, message, details and metadata" do
        detail = Google::Protobuf::Any.pack(TestMessages::EchoRequest.new(text: "why"))
        body = JSON.generate(
          code: "not_found",
          message: "no such thing",
          details: [{type: "connect_rpc_httpx.test.EchoRequest", value: Base64.strict_encode64(detail.value).delete("=")}],
        )
        stub_request(:post, url).to_return(
          status: 404,
          headers: {"content-type" => "application/json", "x-h" => "1", "trailer-x-t" => "2"},
          body:,
        )

        expect { client.call_unary(method_descriptor, request) }.to raise_error(ConnectRpcHttpx::Error) { |e|
          expect(e.code).to eq(:not_found)
          expect(e.message).to eq("no such thing")
          expect(e.details).to eq([detail])
          expect(e.headers).to include("x-h" => ["1"])
          expect(e.trailers).to eq("x-t" => ["2"])
        }
      end

      it "maps the HTTP status when the code is not a Connect code" do
        stub_request(:post, url).to_return(error_response(429, '{"code":"bogus","message":"m"}'))

        expect { client.call_unary(method_descriptor, request) }
          .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:unavailable) }
      end
    end

    context "when the server answers with a non-Connect error" do
      [[400, :internal], [401, :unauthenticated], [404, :unimplemented], [503, :unavailable], [418, :unknown]].each do |status, code|
        it "maps HTTP #{status} to #{code}" do
          stub_request(:post, url).to_return(error_response(status, "<html></html>", content_type: "text/html"))

          expect { client.call_unary(method_descriptor, request) }
            .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(code) }
        end
      end

      it "maps a JSON body that is not an object by HTTP status" do
        stub_request(:post, url).to_return(error_response(401, "[]"))

        expect { client.call_unary(method_descriptor, request) }
          .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:unauthenticated) }
      end
    end

    context "when a 200 response is not the requested codec" do
      it "raises internal for another Connect codec" do
        stub_request(:post, url).to_return(status: 200, headers: {"content-type" => "application/json"}, body: "{}")

        expect { client.call_unary(method_descriptor, request) }
          .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:internal) }
      end

      it "raises unknown for a non-Connect body" do
        stub_request(:post, url).to_return(status: 200, headers: {"content-type" => "text/html"}, body: "<html>")

        expect { client.call_unary(method_descriptor, request) }
          .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:unknown) }
      end
    end

    it "raises internal for a body that does not decode" do
      stub_request(:post, url).to_return(status: 200, headers: {"content-type" => "application/proto"}, body: "\xff\xff")

      expect { client.call_unary(method_descriptor, request) }
        .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:internal) }
    end

    it "raises unavailable for a transport failure, keeping the cause" do
      stub_request(:post, url).to_raise(HTTPX::ConnectionError.new("refused"))

      expect { client.call_unary(method_descriptor, request) }.to raise_error(ConnectRpcHttpx::Error) { |e|
        expect(e.code).to eq(:unavailable)
        expect(e.cause).to be_a(HTTPX::ConnectionError)
      }
    end

    it "raises unknown for a response that is not valid HTTP" do
      stub_request(:post, url).to_raise(HTTPX::Parser::Error.new("wrong status code (800)"))

      expect { client.call_unary(method_descriptor, request) }
        .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:unknown) }
    end

    it "raises deadline_exceeded when the deadline passes in flight" do
      stub_request(:post, url).to_timeout

      expect { client.call_unary(method_descriptor, request, timeout: 1) }
        .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:deadline_exceeded) }
    end

    it "serves concurrent calls from several threads" do
      stub_request(:post, url).to_return(proto_response(5))

      results = Array.new(8) { Thread.new { client.call_unary(method_descriptor, request).message.count } }.map(&:value)

      expect(results).to all(eq(5))
    end
  end
end
