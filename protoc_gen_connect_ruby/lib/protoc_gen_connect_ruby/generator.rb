# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

require "google/protobuf/plugin_pb"

module ProtocGenConnectRuby
  # Turns a CodeGeneratorRequest into the files to write: a *_connect.rb client and its
  # *_connect.rbs signature for every requested .proto file that declares a service.
  class Generator
    Feature = Google::Protobuf::Compiler::CodeGeneratorResponse::Feature #: singleton(Google::Protobuf::Compiler::CodeGeneratorResponse::Feature)

    # Generated code depends on no field-level features, so every edition protoc knows is accepted.
    SUPPORTED_FEATURES = Feature::FEATURE_PROTO3_OPTIONAL | Feature::FEATURE_SUPPORTS_EDITIONS #: Integer
    MINIMUM_EDITION = Google::Protobuf::Edition::EDITION_PROTO2 #: Integer
    MAXIMUM_EDITION = Google::Protobuf::Edition::EDITION_2024 #: Integer

    attr_reader :request #: Google::Protobuf::Compiler::CodeGeneratorRequest

    #: (Google::Protobuf::Compiler::CodeGeneratorRequest request) -> void
    def initialize(request)
      @request = request
    end

    # A generation failure is reported in the response's error field, as protoc expects.
    #: () -> Google::Protobuf::Compiler::CodeGeneratorResponse
    def run
      Google::Protobuf::Compiler::CodeGeneratorResponse.new(
        supported_features: SUPPORTED_FEATURES,
        minimum_edition: MINIMUM_EDITION,
        maximum_edition: MAXIMUM_EDITION,
        file: generate_files,
      )
    rescue Error => e
      Google::Protobuf::Compiler::CodeGeneratorResponse.new(error: e.message)
    end

    #: () -> Array[Google::Protobuf::Compiler::CodeGeneratorResponse::File]
    private def generate_files
      raise Error, "unknown parameter: #{request.parameter}" unless request.parameter.empty?

      files = request.proto_file.to_a
      type_names = TypeNames.new(files)
      by_name = files.to_h { |file| [file.name, file] }
      request.file_to_generate.flat_map do |name|
        generator = FileGenerator.new(by_name.fetch(name), type_names)
        next [] unless generator.services?

        [
          output_file(Naming.output_path(name, ".rb"), generator.ruby_source),
          output_file(Naming.output_path(name, ".rbs"), generator.rbs_source),
        ]
      end
    end

    #: (String name, String content) -> Google::Protobuf::Compiler::CodeGeneratorResponse::File
    private def output_file(name, content)
      Google::Protobuf::Compiler::CodeGeneratorResponse::File.new(name:, content:)
    end
  end
end
