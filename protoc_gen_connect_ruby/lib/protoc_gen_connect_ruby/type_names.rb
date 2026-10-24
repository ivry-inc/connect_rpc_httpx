# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ProtocGenConnectRuby
  # Resolves fully-qualified message names, as method input and output types spell them, to
  # the absolute Ruby constants protoc's Ruby generator defines for them.
  class TypeNames
    # @rbs @constants: Hash[String, String]

    #: (Array[Google::Protobuf::FileDescriptorProto] files) -> void
    def initialize(files)
      @constants = {}
      files.each do |file|
        proto_prefix = file.package.empty? ? "" : ".#{file.package}"
        ruby_prefix = Naming.package_modules(file).map { |mod| "::#{mod}" }.join
        file.message_type.each { |message| register(message, proto_prefix, ruby_prefix) }
      end
      @constants.freeze
      freeze
    end

    # The Ruby constant for a type name such as ".acme.v1.Outer.Inner".
    #: (String type_name) -> String
    def fetch(type_name)
      @constants.fetch(type_name) { raise Error, "unknown message type: #{type_name}" }
    end

    #: (Google::Protobuf::DescriptorProto message, String proto_prefix, String ruby_prefix) -> void
    private def register(message, proto_prefix, ruby_prefix)
      proto_name = "#{proto_prefix}.#{message.name}"
      ruby_name = "#{ruby_prefix}::#{Naming.rubify_constant(message.name)}"
      @constants[proto_name] = ruby_name
      message.nested_type.each { |nested| register(nested, proto_name, ruby_name) }
    end
  end
end
