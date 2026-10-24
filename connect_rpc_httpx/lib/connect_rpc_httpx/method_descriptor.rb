# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ConnectRpcHttpx
  # @rbs!
  #   # A generated protobuf message class, seen through the class methods the codecs call.
  #   interface _MessageClass[M]
  #     def encode: (M message) -> String
  #     def decode: (String bytes) -> M
  #     def encode_json: (M message) -> String
  #     def decode_json: (String json, ?ignore_unknown_fields: bool) -> M
  #   end

  # One RPC of a service: where it is served and the message classes it exchanges.
  # Generated clients hold one per method as a constant.
  #
  # @rbs generic I -- the request message
  # @rbs generic O -- the response message
  class MethodDescriptor
    # The idempotency_level method option values, as symbols.
    IDEMPOTENCY_LEVELS = [:idempotency_unknown, :no_side_effects, :idempotent].freeze #: Array[Symbol]

    # The fully-qualified service name, such as "acme.greet.v1.GreetService".
    attr_reader :service #: String

    # The method name as declared in the .proto file, such as "Greet".
    attr_reader :name #: String

    attr_reader :input #: _MessageClass[I]
    attr_reader :output #: _MessageClass[O]
    attr_reader :idempotency #: Symbol

    #: (service: String, name: String, input: _MessageClass[I], output: _MessageClass[O], ?idempotency: Symbol) -> void
    def initialize(service:, name:, input:, output:, idempotency: :idempotency_unknown)
      raise ArgumentError, "unknown idempotency level: #{idempotency.inspect}" unless IDEMPOTENCY_LEVELS.include?(idempotency)

      @service = service
      @name = name
      @input = input
      @output = output
      @idempotency = idempotency
      freeze
    end

    # The URL path the method is served at, relative to the server's base URL.
    #: () -> String
    def path
      "/#{service}/#{name}"
    end

    # Whether the method may be called with Connect GET.
    #: () -> bool
    def no_side_effects?
      idempotency == :no_side_effects
    end
  end
end
