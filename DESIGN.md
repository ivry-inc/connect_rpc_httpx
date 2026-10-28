# Design

## Layout

Two gems share this repository, each a self-contained gem directory released on its own:

- `protoc_gen_connect_ruby/`: the protoc plugin. It depends only on google-protobuf, and is needed only where code is generated.
- `connect_rpc_httpx/`: the runtime generated code requires, built on httpx.

Tooling is shared at the root: one bundle (development dependencies live in the root Gemfile, not the gemspecs), one Steepfile with a target per gem, one RuboCop and hk configuration, and a Rakefile that runs both gems' specs and namespaces their release tasks (`rake connect_rpc_httpx:release`).

## Generated code

For `foo/bar.proto`, the plugin writes `foo/bar_connect.rb` and `foo/bar_connect.rbs` next to protoc's `foo/bar_pb.rb`. Each service becomes `<Service>Client < ConnectRpcHttpx::Client` in the module protoc's Ruby generator puts the messages in, so the plugin reproduces that generator's naming (`Naming`, `TypeNames`), `ruby_package` included.

A client class holds one `ConnectRpcHttpx::MethodDescriptor` constant per RPC and a snake_case method calling it. The descriptors carry everything the runtime needs (path, message classes, idempotency level, stream type), so the generated methods are one-liners calling `call_unary`, `call_client_stream`, `call_server_stream` or `call_bidi_stream`, and all protocol logic lives in the runtime. Unary and client-streaming methods return the response message; `call_unary` and `call_client_stream` with a descriptor return it with the response headers and trailers.

A request may be a message or a Hash of its fields, which google-protobuf turns into the message, nested Hashes and Arrays included. A method taking one request also takes its fields as keyword arguments (`**fields`), passing them on through `Client#request_from`. The `headers:` and `timeout:` options take precedence, so request fields of those names have no keyword form.

The RBS side gives each client a type alias per message its requests reach, transitively: `greet_request_init = GreetRequest | { ?name: ::String?, ... }`. Message fields refer to the aliases of their types, so a recursive message gives a recursive alias. Enum fields are a union of the value names as Symbols and `::Integer`, and `google.protobuf.Timestamp` also takes `::Time`, as google-protobuf does. The aliases are declared in each client class rather than once per message, so a signature depends on no other generated file. `signatures_spec` type checks `spec/fixtures/steep/usage.rb` against them.

Naming conflicts are resolved at generation time: an RPC whose Ruby name matches a method of `ConnectRpcHttpx::Client` or `Object`, private ones included, gets a trailing underscore, and two RPCs that map to the same Ruby name fail generation.

## Runtime

### Thread safety

A `Client` freezes itself in `initialize`, along with its headers, and holds no per-call state. Each call builds its own request headers and reads the response into new objects. The only shared mutable state is the httpx session, whose connection pool is thread-safe since httpx 1.4. The default session uses httpx's `persistent` plugin so connections are reused between calls. Pass `http:` to share one session between clients.

### Deadlines

A `timeout:` is sent as `connect-timeout-ms` and also enforced locally with httpx's `total_request_timeout`. A timeout of zero or less fails with `deadline_exceeded` without sending.

### Errors

Every failure surfaces as `ConnectRpcHttpx::Error`:

| Situation | Code |
|---|---|
| Non-200 response with a Connect error body | the body's code, or the HTTP status mapping when the code is missing or unknown |
| Non-200 response without a Connect error body | the protocol's HTTP status mapping (`Code.from_http_status`) |
| 200 response in another Connect codec | `internal` |
| 200 response that is not a Connect message | `unknown` |
| Undecodable response message, unsupported `content-encoding` | `internal` |
| Response that is not valid HTTP (httpx parser error) | `unknown` |
| httpx timeout with a deadline set | `deadline_exceeded` |
| Any other transport failure | `unavailable` |

Transport failures keep the httpx error as `cause`. Response headers and trailers are kept on the error whenever a response arrived.

### Streaming

Streams use the Connect streaming protocol: enveloped messages (`Envelope`), and an end-of-stream message carrying the trailers and any error. `StreamCall` runs one streaming RPC through a session derived from the client's with httpx's `stream` plugin, built once in `Client#initialize` so the client stays frozen.

- A `ResponseStream` sends its RPC when first iterated and can be iterated once. Client-streaming calls read one through and require exactly one message.
- The caller's block and request Enumerable run inside httpx's event loop. An exception from them propagates as it is. The http-2 gem wraps exceptions raised in its callbacks, so the original is recovered through `cause`.
- Leaving an iteration early, by `break` or exception, leaves the response half read on its connection. The request is failed through `Request#handle_error`, which closes the connection rather than letting the next request read the rest.
- httpx closes a connection idle longer than its operation timeout, 60 seconds for the stream plugin. A stream may stay quiet longer, so `StreamCall` sets it to a year (httpx rejects infinity), leaving the deadline to `total_request_timeout`.
- httpx 1.9 ends a chunked HTTP/1.1 request body without its final CRLF unless the request has trailers, and a server then waits for the rest of the body. `StreamCall` gives each request empty trailers to work around it.
- Bidirectional streams are half-duplex. Full duplex needs httpx's `stream_bidi` plugin and HTTP/2, and an API to send and receive independently.

### Conformance

`conformance/` runs the official Connect conformance suite in client mode against a client generated from the suite's own protos, so it covers the plugin and the runtime together. See [conformance/README.md](conformance/README.md) for scope and known failures.

## Types

- Both gems are typed with rbs-inline annotations, generated into each gem's `sig/generated`. The directory is committed and shipped, and CI fails when it differs from a fresh `rake rbs`, because an annotation can change without anyone regenerating.
- `rbs/google-protobuf/` is a local rbs collection source for the google-protobuf 4.x surface both gems use. The gem ships no signatures, and ruby/gem_rbs_collection's entry stops at 3.22.
- httpx ships its own signatures, which need the `forwardable` and `openssl` stdlib signatures loaded (Steepfile). `rake rbs` does not run `rbs validate`, which would also check httpx's signatures for plugins whose optional gems are not installed; `steep check` validates this project's signatures.
- The generated `*_connect.rbs` files reference `ConnectRpcHttpx::MethodDescriptor[I, O]`, `ConnectRpcHttpx::seconds` and the message classes, so they type-check against the runtime's shipped signatures plus whatever signatures the application has for its messages.

### Documentation

- RDoc 8 reads the `#:` signatures itself and renders them with each method (`rake rdoc`).
- YARD does not, so `yard/rbs_inline.rb` rewrites each `#:` method signature into a yard-sig `@!sig` directive, which expands into `@param` and `@return` tags, and drops `@rbs` annotations (`rake yard`).
