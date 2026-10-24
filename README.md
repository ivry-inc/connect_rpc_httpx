# connect_rpc_httpx: Typed Connect RPC clients for Ruby, on httpx

connect_rpc_httpx is a [Connect](https://connectrpc.com/) RPC client for Ruby that speaks the Connect protocol over [httpx](https://gitlab.com/os85/httpx). Its companion protoc plugin, protoc-gen-connect-ruby, generates the clients from your `.proto` files: each service becomes a plain Ruby class with one method per RPC, along with an RBS signature so Steep can check the calls.

Unary RPCs, client and server streams, and half-duplex bidirectional streams are supported, and checked against the official [Connect conformance suite](conformance/).

## Features

- A client per service, in the module protoc's Ruby generator puts the messages in, with snake_case methods
- Server streams yield messages to a block or as an Enumerable; client streams take any Enumerable, including a lazy one
- RBS signatures for every generated client, typed against your message classes
- One client instance can be shared between threads: it is frozen after construction, and httpx pools its connections
- Connect GET for RPCs marked `idempotency_level = NO_SIDE_EFFECTS`, so caches and proxies can serve them
- proto and JSON codecs, over HTTP/1.1 or HTTP/2, with or without TLS
- Every failure raises `ConnectRpcHttpx::Error` with the Connect code, details, and response metadata

## Gems

This repository holds two gems:

| Gem | Needed | What |
|---|---|---|
| [`protoc_gen_connect_ruby`](protoc_gen_connect_ruby/) | where code is generated | the `protoc-gen-connect-ruby` plugin for protoc and buf |
| [`connect_rpc_httpx`](connect_rpc_httpx/) | where the clients run | the runtime: client base class, codecs, errors |

Neither is released to RubyGems.org yet. Both require Ruby 3.4 or later.

## Quick start

### 1. Add the gems

```ruby
# Gemfile
gem "protoc_gen_connect_ruby", group: :development
gem "connect_rpc_httpx"
```

### 2. Generate

The plugin runs next to protoc's built-in Ruby generator, which writes the message classes:

```yaml
# buf.gen.yaml
version: v2
plugins:
  - protoc_builtin: ruby
    out: lib/gen
  - local: [bundle, exec, protoc-gen-connect-ruby]
    out: lib/gen
```

```
buf generate proto
```

For `proto/acme/greet/v1/greet.proto`, this writes `greet_pb.rb`, `greet_connect.rb` and `greet_connect.rbs` under `lib/gen/acme/greet/v1/`. With protoc instead of buf: `protoc --ruby_out=lib/gen --connect-ruby_out=lib/gen acme/greet/v1/greet.proto`.

### 3. Call

Generated files require each other by path, as protoc's Ruby output does, so the output directory goes on the load path:

```ruby
$LOAD_PATH.unshift(File.expand_path("lib/gen", __dir__))
require "acme/greet/v1/greet_connect"

client = Acme::Greet::V1::GreetServiceClient.new("https://api.example.com", timeout: 5)
response = client.greet(Acme::Greet::V1::GreetRequest.new(name: "Ruby"))
response.greeting
```

The [connect_rpc_httpx README](connect_rpc_httpx/) covers client options, per-call headers and deadlines, response metadata and errors. The [protoc_gen_connect_ruby README](protoc_gen_connect_ruby/) covers the generated code and its type signatures.

## Caveats

- Full-duplex bidirectional streaming, the gRPC and gRPC-Web protocols, and request compression are not implemented. A bidirectional RPC sends all of its requests before reading responses.
- A call blocks its thread and cannot be cancelled from another one. A stream is cancelled by leaving its iteration.
- Type-checking calls into generated clients needs RBS for the message classes too, which this plugin does not write.

## Related

- [connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) serves Connect unary RPCs from a Rails app, for the server side.

## Development

```sh
mise install
hk install
bin/setup
bundle exec rake          # specs and steep, for both gems
mise run conformance      # the Connect conformance suite, see conformance/
bundle exec rake yard     # API docs into doc/yard (or rake rdoc)
```

[DESIGN.md](DESIGN.md) describes how the pieces fit together.

## License

Apache-2.0. Copyright 2026 IVRy Inc. See [LICENSE](LICENSE).
