# frozen_string_literal: true

# mise.toml pins the runner; the protos are generated from the BSR module of the same version.
def conformance_version
  File.read(File.expand_path("../mise.toml", __dir__))[/^"github:connectrpc\/conformance" = "([^"]+)"/, 1] or
    raise "connectrpc/conformance is not pinned in mise.toml"
end

desc "Run the Connect conformance suite against a client built from the generated code"
task :conformance do
  Dir.chdir("conformance") { sh "buf", "generate", "buf.build/connectrpc/conformance:v#{conformance_version}" }
  sh(
    "connectconformance", "--mode", "client", "--conf", "conformance/config.yaml",
    "--known-failing", "@conformance/known_failing.txt",
    "--", "bundle", "exec", "ruby", "conformance/client.rb"
  )
end
