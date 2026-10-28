# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ProtocGenConnectRuby
  # Resolves fully-qualified type names, as method input and output types and fields spell them,
  # to their descriptors and to the absolute Ruby constants protoc's Ruby generator defines for
  # messages.
  class TypeNames
    # @rbs @constants: Hash[String, String]
    # @rbs @messages: Hash[String, Google::Protobuf::DescriptorProto]
    # @rbs @enums: Hash[String, Google::Protobuf::EnumDescriptorProto]

    #: (Array[Google::Protobuf::FileDescriptorProto] files) -> void
    def initialize(files)
      @constants = {}
      @messages = {}
      @enums = {}
      files.each do |file|
        proto_prefix = file.package.empty? ? "" : ".#{file.package}"
        ruby_prefix = Naming.package_modules(file).map { |mod| "::#{mod}" }.join
        file.message_type.each { |message| register(message, proto_prefix, ruby_prefix) }
        file.enum_type.each { |enum| @enums["#{proto_prefix}.#{enum.name}"] = enum }
      end
      @constants.freeze
      @messages.freeze
      @enums.freeze
      freeze
    end

    # The Ruby constant for a message type name such as ".acme.v1.Outer.Inner".
    #: (String type_name) -> String
    def fetch(type_name)
      @constants.fetch(type_name) { raise Error, "unknown message type: #{type_name}" }
    end

    #: (String type_name) -> Google::Protobuf::DescriptorProto
    def message(type_name)
      @messages.fetch(type_name) { raise Error, "unknown message type: #{type_name}" }
    end

    #: (String type_name) -> Google::Protobuf::EnumDescriptorProto
    def enum(type_name)
      @enums.fetch(type_name) { raise Error, "unknown enum type: #{type_name}" }
    end

    #: (Google::Protobuf::DescriptorProto message, String proto_prefix, String ruby_prefix) -> void
    private def register(message, proto_prefix, ruby_prefix)
      proto_name = "#{proto_prefix}.#{message.name}"
      ruby_name = "#{ruby_prefix}::#{Naming.rubify_constant(message.name)}"
      @constants[proto_name] = ruby_name
      @messages[proto_name] = message
      message.nested_type.each { |nested| register(nested, proto_name, ruby_name) }
      message.enum_type.each { |enum| @enums["#{proto_name}.#{enum.name}"] = enum }
    end
  end
end
