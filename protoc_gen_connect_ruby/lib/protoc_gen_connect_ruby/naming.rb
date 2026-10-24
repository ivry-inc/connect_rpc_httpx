# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ProtocGenConnectRuby
  # Ruby names for protobuf declarations. Modules and message classes follow protoc's Ruby
  # generator (src/google/protobuf/compiler/ruby/ruby_generator.cc), so generated clients refer to
  # the constants that *_pb.rb files define.
  module Naming
    # The module path a file's messages are defined under, outermost first. The ruby_package
    # option wins over the proto package, and is taken verbatim when it is written with "::".
    #: (Google::Protobuf::FileDescriptorProto file) -> Array[String]
    def self.package_modules(file)
      options = file.options
      ruby_package = options&.ruby_package.to_s
      if ruby_package.include?("::")
        ruby_package.split("::")
      else
        package = ruby_package.empty? ? file.package : ruby_package
        package.split(".").map { |component| package_to_module(component) }
      end
    end

    # foo_bar -> FooBar
    #: (String component) -> String
    def self.package_to_module(component)
      component.split("_").reject(&:empty?).map { |part| part[0].to_s.upcase + part[1..].to_s }.join
    end

    # Capitalizes a message or enum name, prefixing "PB_" when it does not start with a letter.
    #: (String name) -> String
    def self.rubify_constant(name)
      case name
      when /\A[a-z]/ then name[0].to_s.upcase + name[1..].to_s
      when /\A[A-Z]/ then name
      else "PB_#{name}"
      end
    end

    # GetHTTPStatus -> get_http_status
    #: (String name) -> String
    def self.underscore(name)
      name
        .gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase
    end

    # The path of a generated file next to its source: foo/bar.proto -> foo/bar_connect.rb
    #: (String proto_path, String extension) -> String
    def self.output_path(proto_path, extension)
      "#{proto_path.delete_suffix(".proto")}_connect#{extension}"
    end

    # The require path of the *_pb.rb file protoc generates for +proto_path+.
    #: (String proto_path) -> String
    def self.pb_require_path(proto_path)
      "#{proto_path.delete_suffix(".proto")}_pb"
    end
  end
end
