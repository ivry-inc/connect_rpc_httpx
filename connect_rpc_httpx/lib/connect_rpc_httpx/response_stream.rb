# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ConnectRpcHttpx
  # The responses of a server-streaming or bidirectional RPC, read as they arrive.
  #
  # The RPC is sent when the stream is first iterated, and a stream can be iterated only once.
  # Leaving the iteration early, with +break+ or an exception, cancels the RPC.
  #
  #   stream = client.watch(request)
  #   stream.each { |event| ... }
  #   stream.trailers
  #
  # @rbs generic O -- the response message
  class ResponseStream
    include Enumerable #[O]

    # @rbs!
    #   # Performs the RPC, reporting the headers and each message, and returns the trailers.
    #   interface _Runner[O]
    #     def run: (^(metadata) -> void on_headers, ^(O) -> void on_message) -> metadata
    #   end

    # @rbs @runner: _Runner[O]
    # @rbs @started: bool

    # Response headers, once the response has started to arrive.
    attr_reader :headers #: metadata?

    # Response trailers, once the stream has ended, including with an error.
    attr_reader :trailers #: metadata?

    #: (_Runner[O] runner) -> void
    def initialize(runner)
      @runner = runner
      @started = false
      @headers = nil
      @trailers = nil
    end

    # Yields each response message. Raises ConnectRpcHttpx::Error when the RPC fails, after any
    # messages that arrived before the failure.
    #: () { (O message) -> void } -> self
    #: () -> Enumerator[O, self]
    def each(&block)
      return enum_for(:each) unless block
      raise ArgumentError, "a response stream can be iterated only once" if @started

      @started = true
      begin
        @trailers = @runner.run(->(headers) { @headers = headers }, block)
      rescue Error => e
        @trailers = e.trailers
        raise
      end
      self
    end
  end
end
