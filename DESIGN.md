# Design

## Layout

Two gems share this repository, each a self-contained gem directory released on its own:

- `protoc_gen_connect_ruby/`: the protoc plugin. It depends only on google-protobuf, and is needed only where code is generated.
- `connect_rpc_httpx/`: the runtime generated code requires, built on httpx.

Tooling is shared at the root: one bundle (development dependencies live in the root Gemfile, not the gemspecs), one Steepfile with a target per gem, one RuboCop and hk configuration, and a Rakefile that runs both gems' specs and namespaces their release tasks (`rake connect_rpc_httpx:release`).

## Generated code

For `foo/bar.proto`, the plugin writes `foo/bar_connect.rb` and `foo/bar_connect.rbs` next to protoc's `foo/bar_pb.rb`. Each service becomes `<Service>Client < ConnectRpcHttpx::Client` in the module protoc's Ruby generator puts the messages in, so the plugin reproduces that generator's naming (`Naming`, `TypeNames`), `ruby_package` included.

A client class holds one `ConnectRpcHttpx::MethodDescriptor` constant per unary RPC and a snake_case method calling it. The descriptors carry everything the runtime needs (path, message classes, idempotency level), so the generated methods are one-liners and all protocol logic lives in the runtime. Generated methods return the response message; `Client#call_unary` with a descriptor returns the message with response headers and trailers.

Naming conflicts are resolved at generation time: an RPC whose Ruby name matches a client or `Object` method gets a trailing underscore, and two RPCs that map to the same Ruby name fail generation.

Streaming RPCs are skipped with a comment until the runtime implements them.

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
