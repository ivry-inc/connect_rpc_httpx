# connect_rpc_httpx: Connect RPC client runtime on httpx

connect_rpc_httpx is the runtime for the [Connect](https://connectrpc.com/) clients that [protoc-gen-connect-ruby](../protoc_gen_connect_ruby/) generates. It speaks the Connect protocol over a persistent [httpx](https://gitlab.com/os85/httpx) session, and a client can be shared freely between threads.

It implements unary RPCs over HTTP POST and Connect GET, and client, server and half-duplex bidirectional streams, with the proto and JSON codecs, over whatever HTTP version and TLS setup the httpx session negotiates. Its behaviour is checked against the official [Connect conformance suite](../conformance/) over HTTP/1.1, HTTP/2 and TLS.

## Installation

Not released to RubyGems.org yet.

```ruby
# Gemfile
gem "connect_rpc_httpx"
```

Requires Ruby 3.4 or later.

## Usage

```ruby
require "acme/greet/v1/greet_connect"

client = Acme::Greet::V1::GreetServiceClient.new(
  "https://api.example.com",
  headers: {"authorization" => "Bearer TOKEN"}, # sent with every RPC
  timeout: 5,                                   # default deadline, in seconds
)

response = client.greet(name: "Ruby")
```

`Client.new` options:

- `codec:` `:proto` (default) or `:json`
- `http:` the `HTTPX::Session` to send through. Defaults to a persistent session owned by the client. Pass your own to add httpx plugins, TLS settings or shared connection pools.
- `headers:` request headers for every RPC
- `timeout:` the default deadline in seconds, sent as `connect-timeout-ms` and enforced locally. `nil` (default) sends none.
- `http_get:` send RPCs marked `idempotency_level = NO_SIDE_EFFECTS` with Connect GET, so caches can serve them

A client freezes itself once built. Build one per server and share it between threads; httpx pools the session's connections behind a lock.

### Per-call options

```ruby
client.greet(request, headers: {"x-request-id" => "abc"}, timeout: 1.5)
```

Call headers are merged over the client's. A call's `timeout:` replaces the client's, and `nil` removes the deadline.

### Authentication and httpx plugins

Every RPC goes through the client's httpx session, so httpx plugins apply to all of them. Build the session and pass it as `http:`:

```ruby
http = HTTPX.plugin(:persistent).plugin(:auth).bearer_auth(ENV.fetch("API_TOKEN"))

client = Acme::Greet::V1::GreetServiceClient.new("https://api.example.com", http:)
```

For a token that changes, give `bearer_auth` a block. httpx caches its result, so set how long the token lasts and the block is called again after that:

```ruby
http = HTTPX.plugin(:persistent)
  .plugin(:auth)
  .with(auth_header_expires_in: 300) # seconds
  .bearer_auth { fetch_token }
```

Other plugins and options chain the same way, such as `.plugin(:retries, max_retries: 2)`, `.plugin(:aws_sigv4, ...)` or `.with(ssl: {...})` for client certificates. Keep `:persistent` in the chain so connections are reused between RPCs. The client never modifies the session, so one session can serve several clients and threads.

A fixed header needs no plugin: pass it as `headers:` to `new`, or to a single call.

### Streaming RPCs

A server-streaming method yields each response message as it arrives, and returns the stream for its metadata:

```ruby
stream = client.greet_stream(request) do |response|
  puts response.greeting
end
stream.headers
stream.trailers
```

Without a block it returns the stream unread, an Enumerable that sends the RPC when first iterated and can be iterated once:

```ruby
stream = client.greet_stream(request)
stream.first(3)   # leaving the iteration early cancels the RPC
```

A client-streaming method takes any Enumerable of requests, messages or Hashes of their fields, such as an Array or a lazy Enumerator, sends each message as it is produced, and returns the single response:

```ruby
client.greet_many(names.lazy.map { |name| Acme::Greet::V1::GreetRequest.new(name:) })
```

A bidirectional method takes an Enumerable as well and yields responses as a server stream does. It is half-duplex: every request is sent before responses are read, which works over HTTP/1.1 and HTTP/2 alike.

A failure raises `ConnectRpcHttpx::Error` during the iteration, after the messages that arrived before it. An exception from your block or from the request Enumerable propagates as it is, and cancels the RPC.

### Response metadata

Generated methods return the response message. For response headers and trailers, call the method descriptor through `call_unary`:

```ruby
result = client.call_unary(Acme::Greet::V1::GreetServiceClient::GREET, request)
result.message  # Acme::Greet::V1::GreetResponse
result.headers  # {"content-type" => ["application/proto"], ...}
result.trailers # {"x-trailer" => ["value"]}
```

### Errors

Every failure raises `ConnectRpcHttpx::Error`: an error the server returned, an unexpected HTTP response, and transport failures (`unavailable`, or `deadline_exceeded` once the deadline passes) alike.

```ruby
begin
  client.greet(request)
rescue ConnectRpcHttpx::Error => e
  e.code     # :not_found, :unavailable, ...
  e.message
  e.details  # [Google::Protobuf::Any, ...]; unpack with e.details.first.unpack(SomeDetail)
  e.headers
  e.trailers
end
```

## Caveats

- Full-duplex bidirectional streaming, the gRPC and gRPC-Web protocols, and request compression are not implemented.
- A call cannot be cancelled from another thread. A stream is cancelled by leaving its iteration.
- Responses compressed with gzip or deflate are decoded by httpx; other encodings fail with `internal`.

## License

Apache-2.0. Copyright 2026 IVRy Inc. See [LICENSE](LICENSE).
