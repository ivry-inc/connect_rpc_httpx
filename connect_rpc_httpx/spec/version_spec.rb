# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe(ConnectRpcHttpx) do
  it "has a version number" do
    expect(ConnectRpcHttpx::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end
end
