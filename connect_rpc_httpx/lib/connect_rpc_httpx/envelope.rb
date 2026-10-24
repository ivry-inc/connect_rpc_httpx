# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ConnectRpcHttpx
  # Connect streaming frames each message in an envelope: one flags byte and a big-endian 32-bit
  # length, followed by the data. See https://connectrpc.com/docs/protocol/#streaming-request.
  module Envelope
    PREFIX_SIZE = 5 #: Integer
    COMPRESSED = 0b01 #: Integer
    # Marks the final envelope of a response stream, whose data is a JSON end-of-stream message.
    END_STREAM = 0b10 #: Integer

    #: (String data, ?Integer flags) -> String
    def self.encode(data, flags = 0)
      [flags, data.bytesize].pack("CN") + data.b
    end

    # Reassembles envelopes from response body chunks, which split them at arbitrary points.
    class Reader
      # @rbs @buffer: String

      #: () -> void
      def initialize
        @buffer = "".b
      end

      # Appends +chunk+ and yields the flags and data of each envelope it completes.
      #: (String chunk) { (Integer flags, String data) -> void } -> void
      def push(chunk)
        @buffer << chunk.b
        while @buffer.bytesize >= PREFIX_SIZE
          flags, length = @buffer.unpack("CN") #: [Integer, Integer]
          break if @buffer.bytesize < PREFIX_SIZE + length

          data = @buffer.byteslice(PREFIX_SIZE, length).to_s
          @buffer = @buffer.byteslice((PREFIX_SIZE + length)..).to_s
          yield flags, data
        end
      end

      # Whether part of an envelope is still waiting for more bytes.
      #: () -> bool
      def partial?
        !@buffer.empty?
      end
    end
  end
end
