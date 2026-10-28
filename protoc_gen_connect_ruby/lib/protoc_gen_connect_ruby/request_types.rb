# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ProtocGenConnectRuby
  # The RBS types of request messages as a client accepts them: the message itself, or a record of
  # its fields that google-protobuf builds the message from. Each message reachable from a request
  # gets a type alias, declared in the client class so the signature needs no other generated file.
  class RequestTypes
    FLOAT = "::Float | ::Integer" #: String

    SCALARS = {
      TYPE_DOUBLE: FLOAT,
      TYPE_FLOAT: FLOAT,
      TYPE_INT64: "::Integer",
      TYPE_UINT64: "::Integer",
      TYPE_INT32: "::Integer",
      TYPE_FIXED64: "::Integer",
      TYPE_FIXED32: "::Integer",
      TYPE_UINT32: "::Integer",
      TYPE_SFIXED32: "::Integer",
      TYPE_SFIXED64: "::Integer",
      TYPE_SINT32: "::Integer",
      TYPE_SINT64: "::Integer",
      TYPE_BOOL: "bool",
      TYPE_STRING: "::String",
      TYPE_BYTES: "::String",
    }.freeze #: Hash[Symbol, String]

    # google-protobuf converts a map key given as a Symbol.
    STRING_KEY = "::String | ::Symbol" #: String

    # Types google-protobuf also converts into a message of the type.
    CONVERTIBLE = {".google.protobuf.Timestamp" => "::Time"}.freeze #: Hash[String, String]

    # @rbs @type_names: TypeNames
    # @rbs @package: String
    # @rbs @aliases: Hash[String, String]

    #: (TypeNames type_names, package: String) -> void
    def initialize(type_names, package:)
      @type_names = type_names
      @package = package
      @aliases = {}
    end

    # The alias for a message type name, registering it and every message its fields reach.
    #: (String type_name) -> String
    def alias_name(type_name)
      @aliases[type_name] || register(type_name)
    end

    # Alias declarations for every registered message, in registration order.
    #: () -> Array[String]
    def declarations
      @aliases.map do |type_name, name|
        types = [@type_names.fetch(type_name), CONVERTIBLE[type_name], record(type_name)].compact
        "type #{name} = #{types.join(" | ")}"
      end
    end

    # Optional keyword parameters for the fields of a message, except those named in +reserved+.
    #: (String type_name, Array[String] reserved) -> Array[String]
    def keywords(type_name, reserved)
      fields(type_name).filter_map do |field|
        "?#{field.name}: #{nilable(field_type(field))}" unless reserved.include?(field.name)
      end
    end

    #: (String type_name) -> String
    private def register(type_name)
      name = unique_name(type_name)
      @aliases[type_name] = name
      fields(type_name).each { |field| field_type(field) }
      name
    end

    #: (String type_name) -> String
    private def record(type_name)
      entries = fields(type_name).map { |field| "?#{field.name}: #{nilable(field_type(field))}" }
      entries.empty? ? "{}" : "{ #{entries.join(", ")} }"
    end

    #: (String type_name) -> Array[Google::Protobuf::FieldDescriptorProto]
    private def fields(type_name)
      @type_names.message(type_name).field.to_a
    end

    #: (Google::Protobuf::FieldDescriptorProto field) -> String
    private def field_type(field)
      if (entry = map_entry(field))
        key, value = entry.field.to_a.sort_by(&:number)
        raise Error, "malformed map entry: #{field.type_name}" unless key && value

        "::Hash[#{key_type(key)}, #{value_type(value)}]"
      elsif field.label == :LABEL_REPEATED
        "::Array[#{value_type(field)}]"
      else
        value_type(field)
      end
    end

    #: (Google::Protobuf::FieldDescriptorProto field) -> String
    private def value_type(field)
      case field.type
      when :TYPE_MESSAGE, :TYPE_GROUP then alias_name(field.type_name)
      when :TYPE_ENUM then "(#{enum_values(field.type_name)})"
      else
        type = SCALARS.fetch(field.type) { raise Error, "unknown field type: #{field.type}" }
        type.include?("|") ? "(#{type})" : type
      end
    end

    #: (Google::Protobuf::FieldDescriptorProto field) -> String
    private def key_type(field)
      field.type == :TYPE_STRING ? "(#{STRING_KEY})" : value_type(field)
    end

    # google-protobuf takes an enum value as its name or its number.
    #: (String type_name) -> String
    private def enum_values(type_name)
      [*@type_names.enum(type_name).value.map { |value| ":#{value.name}" }, "::Integer"].join(" | ")
    end

    #: (Google::Protobuf::FieldDescriptorProto field) -> Google::Protobuf::DescriptorProto?
    private def map_entry(field)
      return unless field.label == :LABEL_REPEATED && field.type == :TYPE_MESSAGE

      message = @type_names.message(field.type_name)
      message if message.options&.map_entry
    end

    # google-protobuf accepts nil for any field, leaving it unset.
    #: (String type) -> String
    private def nilable(type)
      "#{type}?"
    end

    # The type name relative to the file's package, in snake_case: greet_request_nested_init.
    #: (String type_name) -> String
    private def unique_name(type_name)
      prefix = @package.empty? ? "." : ".#{@package}."
      relative = type_name.start_with?(prefix) ? type_name.delete_prefix(prefix) : type_name.delete_prefix(".")
      base = relative.split(".").map { |part| Naming.underscore(part) }.join("_")
      base = "pb_#{base}" unless base.match?(/\A[a-z]/)
      taken = @aliases.values
      name = "#{base}_init"
      suffix = 1
      name = "#{base}_#{suffix += 1}_init" while taken.include?(name)
      name
    end
  end
end
