# frozen_string_literal: true

# YARD reads .yardopts, and so its --load, more than once.
return if defined?(RbsInlineDocstringParser)

require "yard"
require "yard-sig"

# Adapts rbs-inline annotations for YARD. A `#:` method signature, which YARD reads as a docstring
# line starting with ": ", becomes yard-sig's `@!sig` directive and so @param and @return tags.
# `@rbs` annotations and `@rbs!` blocks only declare types for rbs-inline, so they are dropped.
# yard-sig cannot render `untyped` as a type argument, so it is shown as `top` (Object).
class RbsInlineDocstringParser < YARD::DocstringParser
  SIGNATURE_LINE = /\A:\s+(?=[\[(])/
  ANNOTATION_LINE = /\A@rbs\s/
  EMBEDDED_BLOCK = /\A@rbs!\s*\z/

  def parse(content, object = nil, handler = nil)
    super(rewrite(content), object, handler)
  end

  private def rewrite(content)
    in_block = false
    content.each_line.filter_map do |line|
      in_block = false if in_block && !line.match?(/\A\s/)
      next if in_block
      if line.match?(EMBEDDED_BLOCK)
        in_block = true
        next
      end
      next if line.match?(ANNOTATION_LINE)

      next line unless line.match?(SIGNATURE_LINE)

      line.sub(SIGNATURE_LINE, "@!sig ").gsub(/\buntyped\b/, "top")
    end.join
  end
end

YARD::Docstring.default_parser = RbsInlineDocstringParser
