# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ProtocGenConnectRuby
  # Renders the client classes of one .proto file, as Ruby and as RBS.
  class FileGenerator
    # Every method of ConnectRpcHttpx::Client, public or private, which a generated method must not
    # override.
    CLIENT_METHODS = [
      :base_url, :call_bidi_stream, :call_client_stream, :call_server_stream, :call_unary, :check_deadline,
      :check_response_content_type, :check_response_encoding, :check_stream_type, :codec, :get, :headers, :http,
      :http_get, :normalize_headers, :post, :read_unary_response, :request_from, :request_headers, :split_metadata,
      :stream_call, :stream_response, :timeout, :timeout_ms, :timeout_options,
    ].freeze #: Array[Symbol]

    # Constants every generated client defines besides its method descriptors.
    CLIENT_CONSTANTS = ["SERVICE_NAME"].freeze #: Array[String]

    # SourceCodeInfo path components (descriptor.proto field numbers).
    SERVICE_FIELD = 6 #: Integer
    METHOD_FIELD = 2 #: Integer

    RBS_HEADERS = "::Hash[::String, ::String | ::Array[::String]]" #: String
    RBS_TIMEOUT = "::ConnectRpcHttpx::seconds?" #: String

    attr_reader :file #: Google::Protobuf::FileDescriptorProto

    # @rbs @type_names: TypeNames
    # @rbs @comments: Hash[Array[Integer], String]

    #: (Google::Protobuf::FileDescriptorProto file, TypeNames type_names) -> void
    def initialize(file, type_names)
      @file = file
      @type_names = type_names
      @comments = leading_comments(file)
    end

    # Whether the file declares any service, and so has anything to generate.
    #: () -> bool
    def services?
      !file.service.empty?
    end

    #: () -> String
    def ruby_source
      out = Writer.new
      out.line("# frozen_string_literal: true")
      header(out)
      out.line("require \"connect_rpc_httpx\"")
      out.line("require \"#{Naming.pb_require_path(file.name)}\"")
      out.line
      modules(out) do
        file.service.each_with_index do |service, index|
          out.line unless index.zero?
          ruby_client(out, service, index)
        end
      end
      out.to_s
    end

    #: () -> String
    def rbs_source
      out = Writer.new
      header(out)
      modules(out) do
        file.service.each_with_index do |service, index|
          out.line unless index.zero?
          rbs_client(out, service, index)
        end
      end
      out.to_s
    end

    #: (Writer out, Google::Protobuf::ServiceDescriptorProto service, Integer index) -> void
    private def ruby_client(out, service, index)
      comment(out, [SERVICE_FIELD, index])
      out.block("class #{client_class(service)} < ::ConnectRpcHttpx::Client") do
        out.line("SERVICE_NAME = #{full_name(service).inspect}")
        indexed_methods(service).each do |method, method_index|
          constant = method_constant(method)
          type = stream_type(method)
          out.line
          out.line("#{constant} = ::ConnectRpcHttpx::MethodDescriptor.new(")
          out.indent do
            out.line("service: SERVICE_NAME,")
            out.line("name: #{method.name.inspect},")
            out.line("input: #{@type_names.fetch(method.input_type)},")
            out.line("output: #{@type_names.fetch(method.output_type)},")
            out.line("idempotency: :#{idempotency(method)},")
            out.line("stream_type: :#{type},") unless type == :unary
          end
          out.line(")")
          out.line
          comment(out, [SERVICE_FIELD, index, METHOD_FIELD, method_index])
          ruby_method_definition(out, method, constant, type)
        end
      end
    end

    #: (Writer out, Google::Protobuf::MethodDescriptorProto method, String constant, Symbol type) -> void
    private def ruby_method_definition(out, method, constant, type)
      name = ruby_method(method)
      case type
      when :unary
        out.block("def #{name}(request, headers: {}, timeout: self.timeout)") do
          out.line("call_unary(#{constant}, request, headers:, timeout:).message")
        end
      when :client_stream
        out.block("def #{name}(requests, headers: {}, timeout: self.timeout)") do
          out.line("call_client_stream(#{constant}, requests, headers:, timeout:).message")
        end
      when :server_stream
        out.block("def #{name}(request, headers: {}, timeout: self.timeout, &)") do
          out.line("call_server_stream(#{constant}, request, headers:, timeout:, &)")
        end
      when :bidi_stream
        out.block("def #{name}(requests, headers: {}, timeout: self.timeout, &)") do
          out.line("call_bidi_stream(#{constant}, requests, headers:, timeout:, &)")
        end
      end
    end

    #: (Writer out, Google::Protobuf::ServiceDescriptorProto service, Integer index) -> void
    private def rbs_client(out, service, index)
      comment(out, [SERVICE_FIELD, index])
      out.block("class #{client_class(service)} < ::ConnectRpcHttpx::Client") do
        out.line("SERVICE_NAME: ::String")
        indexed_methods(service).each do |method, method_index|
          input = @type_names.fetch(method.input_type)
          output = @type_names.fetch(method.output_type)
          out.line
          out.line("#{method_constant(method)}: ::ConnectRpcHttpx::MethodDescriptor[#{input}, #{output}]")
          out.line
          comment(out, [SERVICE_FIELD, index, METHOD_FIELD, method_index])
          out.line("def #{ruby_method(method)}: #{rbs_method_type(stream_type(method), input, output)}")
        end
      end
    end

    #: (Symbol type, String input, String output) -> String
    private def rbs_method_type(type, input, output)
      options = "?headers: #{RBS_HEADERS}, ?timeout: #{RBS_TIMEOUT}"
      stream = "::ConnectRpcHttpx::ResponseStream[#{output}]"
      case type
      when :client_stream then "(::Enumerable[#{input}] requests, #{options}) -> #{output}"
      when :server_stream then "(#{input} request, #{options}) ?{ (#{output} message) -> void } -> #{stream}"
      when :bidi_stream then "(::Enumerable[#{input}] requests, #{options}) ?{ (#{output} message) -> void } -> #{stream}"
      else "(#{input} request, #{options}) -> #{output}"
      end
    end

    # Methods paired with their index in the service, which SourceCodeInfo paths use.
    #: (Google::Protobuf::ServiceDescriptorProto service) -> Array[[Google::Protobuf::MethodDescriptorProto, Integer]]
    private def indexed_methods(service)
      methods = service_methods(service).each_with_index.to_a
      check_collisions(service, methods.map(&:first))
      methods
    end

    # Read by name, because a "method" accessor would shadow Object#method.
    #: (Google::Protobuf::ServiceDescriptorProto service) -> Array[Google::Protobuf::MethodDescriptorProto]
    private def service_methods(service)
      service["method"].to_a
    end

    #: (Google::Protobuf::MethodDescriptorProto method) -> Symbol
    private def stream_type(method)
      if method.client_streaming
        method.server_streaming ? :bidi_stream : :client_stream
      else
        method.server_streaming ? :server_stream : :unary
      end
    end

    #: (Google::Protobuf::ServiceDescriptorProto service, Array[Google::Protobuf::MethodDescriptorProto] methods) -> void
    private def check_collisions(service, methods)
      seen = {} #: Hash[String, String]
      methods.each do |method|
        ruby_name = ruby_method(method)
        if (other = seen[ruby_name])
          raise Error, "#{full_name(service)}: #{other} and #{method.name} both map to the Ruby method #{ruby_name}"
        end

        seen[ruby_name] = method.name
      end
    end

    # A suffix keeps an RPC from overriding a method the client relies on.
    #: (Google::Protobuf::MethodDescriptorProto method) -> String
    private def ruby_method(method)
      name = Naming.underscore(method.name)
      reserved = CLIENT_METHODS.include?(name.to_sym) || Object.method_defined?(name) || Object.private_method_defined?(name)
      reserved ? "#{name}_" : name
    end

    #: (Google::Protobuf::MethodDescriptorProto method) -> String
    private def method_constant(method)
      name = Naming.underscore(method.name).upcase
      CLIENT_CONSTANTS.include?(name) ? "#{name}_" : name
    end

    #: (Google::Protobuf::ServiceDescriptorProto service) -> String
    private def client_class(service)
      "#{Naming.rubify_constant(service.name)}Client"
    end

    #: (Google::Protobuf::ServiceDescriptorProto service) -> String
    private def full_name(service)
      file.package.empty? ? service.name : "#{file.package}.#{service.name}"
    end

    #: (Google::Protobuf::MethodDescriptorProto method) -> String
    private def idempotency(method)
      level = method.options&.idempotency_level || :IDEMPOTENCY_UNKNOWN
      level.to_s.downcase
    end

    #: (Writer out) -> void
    private def header(out)
      out.line("# Code generated by protoc-gen-connect-ruby #{VERSION}. DO NOT EDIT.")
      out.line("# source: #{file.name}")
      out.line
    end

    #: (Writer out) { () -> void } -> void
    private def modules(out, &block)
      names = Naming.package_modules(file)
      open_modules = ->(rest) do
        if rest.empty?
          block.call
        else
          out.block("module #{rest.first}") { open_modules.call(rest.drop(1)) }
        end
      end
      open_modules.call(names)
    end

    #: (Writer out, Array[Integer] path) -> void
    private def comment(out, path)
      text = @comments[path] or return

      text.chomp.each_line(chomp: true) { |line| out.line("##{line}".rstrip) }
    end

    #: (Google::Protobuf::FileDescriptorProto file) -> Hash[Array[Integer], String]
    private def leading_comments(file)
      comments = {} #: Hash[Array[Integer], String]
      file.source_code_info&.location&.each do |location|
        text = location.leading_comments
        comments[location.path.to_a] = text unless text.empty?
      end
      comments
    end
  end
end
