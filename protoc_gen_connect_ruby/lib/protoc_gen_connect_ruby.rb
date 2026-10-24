# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

require_relative "protoc_gen_connect_ruby/version"
require_relative "protoc_gen_connect_ruby/naming"
require_relative "protoc_gen_connect_ruby/type_names"
require_relative "protoc_gen_connect_ruby/writer"
require_relative "protoc_gen_connect_ruby/file_generator"
require_relative "protoc_gen_connect_ruby/generator"

# A protoc plugin generating Connect RPC clients for the connect_rpc_httpx runtime.
module ProtocGenConnectRuby
  # A request the generator cannot serve, reported back to protoc.
  class Error < StandardError; end

  # Runs the plugin protocol: a CodeGeneratorRequest on +input+, the response on +output+.
  #: (IO input, IO output) -> void
  def self.run(input, output)
    request = Google::Protobuf::Compiler::CodeGeneratorRequest.decode(input.binmode.read.to_s)
    response = Generator.new(request).run
    output.binmode.write(Google::Protobuf::Compiler::CodeGeneratorResponse.encode(response))
  end
end
