# frozen_string_literal: true

require_relative "../spec_helper"
require "connect_rpc_httpx"
require "webmock/rspec"
require "httpx/adapters/webmock"

RSpec.describe("protoc-gen-connect-ruby") do
  # Runs the executable as protoc does, next to protoc's own Ruby output, and loads both once:
  # protobuf rejects a second load of the same .proto into its descriptor pool.
  before(:context) do
    out = Dir.mktmpdir
    lib = File.expand_path("../../lib", __dir__)
    protoc(
      "--plugin=protoc-gen-connect-ruby=#{ProtocHelper::EXE}",
      "--connect-ruby_out=#{out}",
      "--ruby_out=#{out}",
      "acme/greet/v1/greet.proto",
      "acme/shapes/v1/shapes.proto",
      env: {"RUBYLIB" => [lib, ENV.fetch("RUBYLIB", nil)].compact.join(File::PATH_SEPARATOR)},
    )
    $LOAD_PATH.unshift(out)
    require "acme/greet/v1/greet_connect"
    require "acme/shapes/v1/shapes_connect"
  ensure
    $LOAD_PATH.delete(out)
    FileUtils.remove_entry(out) if out
  end

  let(:client) { Acme::Greet::V1::GreetServiceClient.new("http://greet.test", http_get: true) }

  it "generates a client whose methods call the RPC and return the response message" do
    stub_request(:post, "http://greet.test/acme.greet.v1.GreetService/Greet")
      .with(body: Acme::Greet::V1::GreetRequest.encode(Acme::Greet::V1::GreetRequest.new(name: "Ruby")))
      .to_return(
        status: 200,
        headers: {"content-type" => "application/proto"},
        body: Acme::Greet::V1::GreetResponse.encode(Acme::Greet::V1::GreetResponse.new(greeting: "Hello, Ruby")),
      )

    response = client.greet(Acme::Greet::V1::GreetRequest.new(name: "Ruby"))

    expect(response).to eq(Acme::Greet::V1::GreetResponse.new(greeting: "Hello, Ruby"))
  end

  it "carries the idempotency level, so NO_SIDE_EFFECTS RPCs can use GET" do
    expect(Acme::Greet::V1::GreetServiceClient::GET_GREETING.idempotency).to eq(:no_side_effects)

    stub = stub_request(:get, %r{\Ahttp://greet\.test/acme\.greet\.v1\.GreetService/GetGreeting\?})
      .to_return(status: 200, headers: {"content-type" => "application/proto"}, body: "")

    expect(client.get_greeting(Acme::Greet::V1::GreetRequest.new)).to eq(Acme::Greet::V1::GreetResponse.new)
    expect(stub).to have_been_requested
  end

  it "describes each RPC's stream type" do
    service = Acme::Greet::V1::GreetServiceClient

    expect([service::GREET, service::GREET_STREAM, service::GREET_MANY, service::CONVERSE].map(&:stream_type))
      .to eq([:unary, :server_stream, :client_stream, :bidi_stream])
  end

  it "reserves every method the runtime's client defines" do
    client_methods = ConnectRpcHttpx::Client.instance_methods(false) + ConnectRpcHttpx::Client.private_instance_methods(false) - [:initialize]

    expect(ProtocGenConnectRuby::FileGenerator::CLIENT_METHODS).to match_array(client_methods)
  end

  it "resolves message types across files and packages" do
    expect(Acme::Shapes::Shape_serviceClient::DESCRIBE.output).to eq(Acme::Greet::V1::GreetResponse)
  end
end
