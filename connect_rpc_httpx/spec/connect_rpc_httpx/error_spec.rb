# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe(ConnectRpcHttpx::Error) do
  it "rejects a code Connect does not define" do
    expect { described_class.new(:bogus) }.to raise_error(ArgumentError)
  end

  it "uses the code as the message when none is given" do
    expect(described_class.new(:not_found).message).to eq("not_found")
  end

  describe ".from_unary_response" do
    def build(body, status: 400, content_type: "application/json")
      described_class.from_unary_response(status:, content_type:, body:, headers: {}, trailers: {})
    end

    it "decodes details in either base64 alphabet, padded or not" do
      bytes = "\xfb\xff".b
      details = [
        {type: "a.B", value: Base64.urlsafe_encode64(bytes, padding: false)},
        {type: "a.B", value: Base64.strict_encode64(bytes)},
      ]

      error = build(JSON.generate(code: "internal", details:))

      expect(error.details.map(&:value)).to eq([bytes, bytes])
      expect(error.details.map(&:type_url)).to all(eq("type.googleapis.com/a.B"))
    end

    it "skips malformed details" do
      error = build(JSON.generate(code: "internal", details: [{type: "a.B"}, "x", {type: "a.B", value: "!!"}]))

      expect(error.details).to be_empty
    end

    it "maps the HTTP status when the body has no code" do
      expect(build('{"message":"m"}', status: 403).code).to eq(:permission_denied)
    end
  end
end
