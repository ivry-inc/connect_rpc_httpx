# frozen_string_literal: true

# Stdlib signatures that httpx's shipped RBS refers to but its manifest does not declare. Every
# target loads the whole rbs collection, so each needs them.
HTTPX_STDLIB = ["forwardable", "openssl"].freeze

target :connect_rpc_httpx do
  signature "connect_rpc_httpx/sig"
  check "connect_rpc_httpx/lib"
  library(*HTTPX_STDLIB, "json", "uri")
end

target :protoc_gen_connect_ruby do
  signature "protoc_gen_connect_ruby/sig"
  check "protoc_gen_connect_ruby/lib"
  library(*HTTPX_STDLIB)
end
