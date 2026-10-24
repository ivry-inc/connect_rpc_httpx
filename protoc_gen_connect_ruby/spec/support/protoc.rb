# frozen_string_literal: true

require "open3"
require "fileutils"
require "tmpdir"
require "google/protobuf/plugin_pb"

module ProtocHelper
  FIXTURES = File.expand_path("../fixtures", __dir__)
  PROTO_ROOT = File.join(FIXTURES, "proto")
  EXE = File.expand_path("../../exe/protoc-gen-connect-ruby", __dir__)

  def protoc(*args, chdir: PROTO_ROOT, env: {})
    out, status = Open3.capture2e(env, "protoc", *args, chdir:)
    raise "protoc failed: #{out}" unless status.success?

    out
  end

  # The request protoc would send the plugin for +files+, built from a descriptor set.
  def code_generator_request(*files, parameter: "")
    Dir.mktmpdir do |dir|
      set_path = File.join(dir, "set.binpb")
      protoc("--include_imports", "--include_source_info", "--descriptor_set_out=#{set_path}", *files)
      set = Google::Protobuf::FileDescriptorSet.decode(File.binread(set_path))
      Google::Protobuf::Compiler::CodeGeneratorRequest.new(file_to_generate: files, parameter:, proto_file: set.file.to_a)
    end
  end
end
