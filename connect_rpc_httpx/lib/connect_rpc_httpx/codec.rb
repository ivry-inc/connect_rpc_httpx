# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ConnectRpcHttpx
  # Message serialization for unary bodies. Both codecs delegate to google-protobuf.
  module Codec
    # @rbs!
    #   interface _Codec
    #     # The codec name, as in "application/<name>" and the GET encoding parameter.
    #     def name: () -> String
    #     def content_type: () -> String
    #     def encode: [M] (_MessageClass[M] message_class, M message) -> String
    #     def decode: [M] (_MessageClass[M] message_class, String bytes) -> M
    #   end

    # The codec registered under +name+, :proto or :json.
    #: (Symbol name) -> _Codec
    def self.fetch(name)
      case name
      when :proto then Proto
      when :json then Json
      else raise ArgumentError, "unknown codec: #{name.inspect}"
      end
    end

    # The media type without parameters, lowercased.
    #: (String? content_type) -> String?
    def self.media_type(content_type)
      content_type&.split(";", 2)&.first&.strip&.downcase
    end

    # The Protobuf binary format.
    module Proto
      NAME = "proto" #: String
      CONTENT_TYPE = "application/proto" #: String

      #: () -> String
      def self.name = NAME

      #: () -> String
      def self.content_type = CONTENT_TYPE

      #: [M] (_MessageClass[M] message_class, M message) -> String
      def self.encode(message_class, message)
        message_class.encode(message)
      end

      #: [M] (_MessageClass[M] message_class, String bytes) -> M
      def self.decode(message_class, bytes)
        message_class.decode(bytes)
      end
    end

    # The Protobuf JSON mapping.
    module Json
      NAME = "json" #: String
      CONTENT_TYPE = "application/json" #: String

      #: () -> String
      def self.name = NAME

      #: () -> String
      def self.content_type = CONTENT_TYPE

      # Whether +content_type+ names JSON, ignoring parameters such as charset.
      #: (String? content_type) -> bool
      def self.content_type?(content_type)
        Codec.media_type(content_type) == CONTENT_TYPE
      end

      #: [M] (_MessageClass[M] message_class, M message) -> String
      def self.encode(message_class, message)
        message_class.encode_json(message)
      end

      # Unknown fields are ignored, so a newer server can add fields without breaking clients.
      #: [M] (_MessageClass[M] message_class, String bytes) -> M
      def self.decode(message_class, bytes)
        message_class.decode_json(bytes, ignore_unknown_fields: true)
      end
    end
  end
end
