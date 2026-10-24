# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ConnectRpcHttpx
  # Response metadata as this library hands it out: lowercase names, each with every value sent.
  module Metadata
    #: (HTTPX::Headers headers) -> Hash[String, Array[String]]
    def self.from_httpx(headers)
      metadata = {} #: Hash[String, Array[String]]
      headers.each do |name, _joined|
        (metadata[name] ||= []).concat(headers.get(name).map(&:to_s))
      end
      metadata
    end
  end
end
