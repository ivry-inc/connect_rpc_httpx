# frozen_string_literal: true

require_relative "lib/protoc_gen_connect_ruby/version"

Gem::Specification.new do |spec|
  spec.name = "protoc_gen_connect_ruby"
  spec.version = ProtocGenConnectRuby::VERSION
  spec.authors = ["IVRy Inc."]
  spec.email = ["arch@ivry.jp"]
  spec.summary = "protoc plugin generating Connect RPC clients for Ruby."
  spec.description = "A protoc / buf plugin that generates Connect RPC client classes and their " \
    "RBS signatures, running on the connect_rpc_httpx runtime."
  spec.homepage = "https://github.com/ivry-inc/connect_rpc_httpx"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/protoc_gen_connect_ruby",
    "rubygems_mfa_required" => "true",
  }

  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["protoc-gen-connect-ruby"]
  spec.require_paths = ["lib"]

  spec.add_dependency "google-protobuf", ">= 4.26"
end
