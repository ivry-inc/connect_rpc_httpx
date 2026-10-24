# protoc_gen_connect_ruby: Connect RPC client generator for Ruby

`protoc-gen-connect-ruby` is a protoc / buf plugin that writes a [Connect](https://connectrpc.com/) client class for every service in your `.proto` files, along with an RBS signature for it. The generated clients run on [connect_rpc_httpx](../connect_rpc_httpx/), which speaks the Connect protocol over [httpx](https://gitlab.com/os85/httpx).

Unary RPCs are supported, over HTTP POST or, for methods marked `idempotency_level = NO_SIDE_EFFECTS`, Connect GET. Streaming RPCs are left out of the generated classes for now.

## Installation

Neither gem is released to RubyGems.org yet. The plugin is needed where code is generated, and the runtime where the generated clients run:

```ruby
# Gemfile
gem "protoc_gen_connect_ruby", group: :development
gem "connect_rpc_httpx"
```

Requires Ruby 3.4 or later.

## Usage

The plugin goes next to protoc's built-in Ruby generator, which writes the message classes the clients use:

```yaml
# buf.gen.yaml
version: v2
plugins:
  - protoc_builtin: ruby
    out: lib/gen
  - local: [bundle, exec, protoc-gen-connect-ruby]
    out: lib/gen
```

or with protoc directly:

```
protoc --ruby_out=lib/gen --connect-ruby_out=lib/gen acme/greet/v1/greet.proto
```

For `acme/greet/v1/greet.proto`, this writes `acme/greet/v1/greet_connect.rb` and `greet_connect.rbs` next to protoc's `greet_pb.rb`. Like protoc's Ruby output, the generated files require each other by path, so the output directory (`lib/gen` here) has to be on the load path. Each service becomes a `<Service>Client` class in the same module as its messages, with one method per RPC, named in snake_case:

```ruby
require "acme/greet/v1/greet_connect"

client = Acme::Greet::V1::GreetServiceClient.new("https://api.example.com")
response = client.greet(Acme::Greet::V1::GreetRequest.new(name: "Ruby"))
response.greeting
```

A method takes `headers:` and `timeout:` (seconds) keywords, returns the response message, and raises `ConnectRpcHttpx::Error` when the RPC fails. See [connect_rpc_httpx](../connect_rpc_httpx/) for the client options, response metadata and errors.

An RPC whose Ruby name would override a method every client has, such as `Class` or `Headers`, gets a trailing underscore: `class_`, `headers_`.

### Type signatures

The `*_connect.rbs` files declare each client against the message classes, so Steep checks calls into the generated clients. Add the output directory to the Steepfile's `signature` list. The message classes themselves need signatures as well, such as those `protoc --rbs_out` writes.

## License

Apache-2.0. Copyright 2026 IVRy Inc. See [LICENSE](LICENSE).
