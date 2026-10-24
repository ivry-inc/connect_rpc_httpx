# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ConnectRpcHttpx
  # Connect status codes, as the snake_case symbols the protocol puts on the wire.
  # See https://connectrpc.com/docs/protocol/#error-codes.
  module Code
    ALL = [
      :canceled,
      :unknown,
      :invalid_argument,
      :deadline_exceeded,
      :not_found,
      :already_exists,
      :permission_denied,
      :resource_exhausted,
      :failed_precondition,
      :aborted,
      :out_of_range,
      :unimplemented,
      :internal,
      :unavailable,
      :data_loss,
      :unauthenticated,
    ].freeze #: Array[Symbol]

    # The protocol's mapping for an HTTP error response that carries no Connect error, such as
    # one from a proxy. Statuses absent here map to :unknown.
    HTTP_STATUS_TO_CODE = {
      400 => :internal,
      401 => :unauthenticated,
      403 => :permission_denied,
      404 => :unimplemented,
      429 => :unavailable,
      502 => :unavailable,
      503 => :unavailable,
      504 => :unavailable,
    }.freeze #: Hash[Integer, Symbol]

    # Whether +code+ is one of the Connect codes.
    #: (Symbol code) -> bool
    def self.valid?(code)
      ALL.include?(code)
    end

    # The code a client reports for an HTTP error status without a Connect error body.
    #: (Integer status) -> Symbol
    def self.from_http_status(status)
      HTTP_STATUS_TO_CODE.fetch(status, :unknown)
    end
  end
end
