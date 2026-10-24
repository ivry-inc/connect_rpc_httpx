# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ConnectRpcHttpx
  # A successful unary RPC: the response message and the metadata that came with it.
  #
  # Metadata keys are lowercase. Trailers arrive as "trailer-" prefixed headers in Connect
  # unary responses, and are listed here without the prefix.
  #
  # @rbs generic O -- the response message
  class UnaryResponse
    attr_reader :message #: O
    attr_reader :headers #: Hash[String, Array[String]]
    attr_reader :trailers #: Hash[String, Array[String]]

    #: (message: O, headers: Hash[String, Array[String]], trailers: Hash[String, Array[String]]) -> void
    def initialize(message:, headers:, trailers:)
      @message = message
      @headers = headers
      @trailers = trailers
      freeze
    end
  end
end
