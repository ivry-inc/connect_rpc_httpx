# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../support/stream_server"

RSpec.describe(ConnectRpcHttpx::Client, "streaming") do
  def descriptor(stream_type)
    ConnectRpcHttpx::MethodDescriptor.new(
      service: "test.v1.EchoService",
      name: "Echo",
      input: TestMessages::EchoRequest,
      output: TestMessages::EchoResponse,
      stream_type:,
    )
  end

  def envelope(count)
    ConnectRpcHttpx::Envelope.encode(TestMessages::EchoResponse.encode(TestMessages::EchoResponse.new(count:)))
  end

  def end_stream(**end_message)
    ConnectRpcHttpx::Envelope.encode(JSON.generate(end_message), ConnectRpcHttpx::Envelope::END_STREAM)
  end

  def sent_messages(request)
    reader = ConnectRpcHttpx::Envelope::Reader.new
    messages = []
    reader.push(request.body) { |_flags, data| messages << TestMessages::EchoRequest.decode(data).text }
    messages
  end

  let(:ok_headers) { {"content-type" => "application/connect+proto", "x-header" => "h"} }
  let(:chunks) { [envelope(1), envelope(2), end_stream(metadata: {"x-trailer" => ["t"]})] }
  let!(:server) do
    response = ->(request) { respond(request) }
    StreamServer.new(&response)
  end
  let(:client) do
    WebMock.allow_net_connect!
    described_class.new(server.url)
  end
  let(:request) { TestMessages::EchoRequest.new(text: "hello") }

  def respond(_request) = [200, ok_headers, chunks]

  after do
    server.stop
    WebMock.disable_net_connect!
  end

  describe "#call_server_stream" do
    it "yields each message and keeps the headers and trailers" do
      counts = []
      stream = client.call_server_stream(descriptor(:server_stream), request) { |message| counts << message.count }

      expect(counts).to eq([1, 2])
      expect(stream.headers).to include("x-header" => ["h"])
      expect(stream.trailers).to eq("x-trailer" => ["t"])
    end

    it "sends the request as one envelope in the Connect streaming content type" do
      client.call_server_stream(descriptor(:server_stream), request).to_a
      sent = server.requests.pop

      expect(sent.path).to eq("/test.v1.EchoService/Echo")
      expect(sent.headers).to include("content-type" => "application/connect+proto", "connect-protocol-version" => "1")
      expect(sent_messages(sent)).to eq(["hello"])
    end

    it "sends nothing until the stream is iterated" do
      stream = client.call_server_stream(descriptor(:server_stream), request)

      expect(server.requests).to be_empty
      expect(stream.map(&:count)).to eq([1, 2])
    end

    it "can be iterated only once" do
      stream = client.call_server_stream(descriptor(:server_stream), request)
      stream.to_a

      expect { stream.to_a }.to raise_error(ArgumentError)
    end

    it "raises the end-of-stream error after the messages before it" do
      allow(self).to receive(:respond).and_return(
        [200, ok_headers, [envelope(1), end_stream(error: {code: "not_found", message: "gone"}, metadata: {"x-t" => ["1"]})]],
      )
      counts = []

      expect { client.call_server_stream(descriptor(:server_stream), request) { |m| counts << m.count } }
        .to raise_error(ConnectRpcHttpx::Error) { |e|
          expect([e.code, e.message, e.trailers]).to eq([:not_found, "gone", {"x-t" => ["1"]}])
          expect(e.headers).to include("x-header" => ["h"])
        }
      expect(counts).to eq([1])
    end

    it "lets an exception from the block through and cancels the stream" do
      error = Class.new(StandardError)

      expect { client.call_server_stream(descriptor(:server_stream), request) { raise error } }.to raise_error(error)
      expect(client.call_server_stream(descriptor(:server_stream), request).map(&:count)).to eq([1, 2])
    end

    it "keeps working after a stream is left early" do
      client.call_server_stream(descriptor(:server_stream), request).first

      expect(client.call_server_stream(descriptor(:server_stream), request).map(&:count)).to eq([1, 2])
    end

    it "maps an HTTP error status like a unary call" do
      allow(self).to receive(:respond).and_return([503, {"content-type" => "text/plain"}, ["down"]])

      expect { client.call_server_stream(descriptor(:server_stream), request).to_a }
        .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:unavailable) }
    end

    {
      "a stream without an end-of-stream message" => [[200, {"content-type" => "application/connect+proto"}, ["\x00\x00\x00\x00\x00".b]], :internal],
      "a compressed message" => [[200, {"content-type" => "application/connect+proto"}, ["\x01\x00\x00\x00\x00".b]], :internal],
      "a message cut off" => [[200, {"content-type" => "application/connect+proto"}, ["\x00\x00\x00\x00\x09ab".b]], :internal],
      "another Connect codec" => [[200, {"content-type" => "application/connect+json"}, [""]], :internal],
      "a non-Connect body" => [[200, {"content-type" => "text/html"}, ["<html>"]], :unknown],
    }.each do |situation, (response, code)|
      it "raises #{code} for #{situation}" do
        allow(self).to receive(:respond).and_return(response)

        expect { client.call_server_stream(descriptor(:server_stream), request).to_a }
          .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(code) }
      end
    end

    it "refuses a descriptor of another stream type" do
      expect { client.call_server_stream(descriptor(:unary), request) }.to raise_error(ArgumentError)
    end
  end

  describe "#call_client_stream" do
    let(:chunks) { [envelope(7), end_stream] }

    it "sends every message and returns the single response" do
      requests = Enumerator.new do |out|
        out << TestMessages::EchoRequest.new(text: "a")
        out << TestMessages::EchoRequest.new(text: "b")
      end

      response = client.call_client_stream(descriptor(:client_stream), requests)

      expect(response.message.count).to eq(7)
      expect(sent_messages(server.requests.pop)).to eq(["a", "b"])
    end

    it "builds each request from a Hash of its fields" do
      client.call_client_stream(descriptor(:client_stream), [{text: "a"}, TestMessages::EchoRequest.new(text: "b")])

      expect(sent_messages(server.requests.pop)).to eq(["a", "b"])
    end

    it "raises unimplemented when the server answers with no message" do
      allow(self).to receive(:respond).and_return([200, ok_headers, [end_stream]])

      expect { client.call_client_stream(descriptor(:client_stream), [request]) }
        .to raise_error(ConnectRpcHttpx::Error) { |e| expect(e.code).to eq(:unimplemented) }
    end

    it "lets an exception from the request Enumerable through" do
      error = Class.new(StandardError)
      requests = Enumerator.new { raise error }

      expect { client.call_client_stream(descriptor(:client_stream), requests) }.to raise_error(error)
    end
  end

  describe "#call_bidi_stream" do
    it "sends every message, then yields the responses" do
      counts = []
      client.call_bidi_stream(descriptor(:bidi_stream), [request, request]) { |message| counts << message.count }

      expect(counts).to eq([1, 2])
      expect(sent_messages(server.requests.pop)).to eq(["hello", "hello"])
    end
  end
end
