# frozen_string_literal: true

require "yard"
require "yard-sig"

# YARD reads an rbs-inline `#:` method signature as a docstring line starting with ": ". This
# rewrites it into yard-sig's `@!sig` directive, which expands to @param and @return tags.
class RbsInlineDocstringParser < YARD::DocstringParser
  SIGNATURE_LINE = /^:\s+(?=[\[(])/

  def parse(content, object = nil, handler = nil)
    super(content.gsub(SIGNATURE_LINE, "@!sig "), object, handler)
  end
end

YARD::Docstring.default_parser = RbsInlineDocstringParser
