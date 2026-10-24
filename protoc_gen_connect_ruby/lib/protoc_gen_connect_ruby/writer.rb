# frozen_string_literal: true
# rbs_inline: enabled

# Copyright 2026 IVRy Inc.
# SPDX-License-Identifier: Apache-2.0

module ProtocGenConnectRuby
  # Accumulates generated source line by line, indenting two spaces per nesting level.
  class Writer
    # @rbs @lines: Array[String]
    # @rbs @depth: Integer

    #: () -> void
    def initialize
      @lines = []
      @depth = 0
    end

    # Appends +text+ at the current indentation. Blank lines carry no indentation.
    #: (?String text) -> void
    def line(text = "")
      @lines << (text.empty? ? "" : "#{"  " * @depth}#{text}")
    end

    #: () { () -> void } -> void
    def indent
      @depth += 1
      yield
    ensure
      @depth -= 1
    end

    # Writes +opening+, the block's lines one level deeper, then "end".
    #: (String opening) { () -> void } -> void
    def block(opening, &)
      line(opening)
      indent(&)
      line("end")
    end

    #: () -> String
    def to_s
      "#{@lines.join("\n")}\n"
    end
  end
end
