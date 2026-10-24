# Connect RPC clients for Ruby

Generate [Connect](https://connectrpc.com/) RPC clients for Ruby from your `.proto` files. Two gems live in this repository:

- [`protoc_gen_connect_ruby`](protoc_gen_connect_ruby/): the `protoc-gen-connect-ruby` plugin for protoc and buf, which writes a client class and its RBS signature for every service.
- [`connect_rpc_httpx`](connect_rpc_httpx/): the runtime those clients run on, speaking the Connect protocol over a thread-safe, persistent [httpx](https://gitlab.com/os85/httpx) session.

## Development

```sh
mise install
hk install
bin/setup
bundle exec rake            # specs and steep
mise run conformance        # the Connect conformance suite, see conformance/
```

## License

Apache-2.0. See [LICENSE](LICENSE).
