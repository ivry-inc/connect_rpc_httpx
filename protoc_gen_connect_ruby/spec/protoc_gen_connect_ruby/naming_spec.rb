# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe(ProtocGenConnectRuby::Naming) do
  describe ".package_modules" do
    def file(package:, ruby_package: nil)
      options = ruby_package && Google::Protobuf::FileOptions.new(ruby_package:)
      Google::Protobuf::FileDescriptorProto.new(name: "x.proto", package:, options:)
    end

    it "capitalizes each package component" do
      expect(described_class.package_modules(file(package: "acme.foo_bar.v1"))).to eq(["Acme", "FooBar", "V1"])
    end

    it "takes a ruby_package written with :: verbatim" do
      expect(described_class.package_modules(file(package: "acme.v1", ruby_package: "ACME::api_v1"))).to eq(["ACME", "api_v1"])
    end

    it "converts a ruby_package written with dots like a package" do
      expect(described_class.package_modules(file(package: "acme.v1", ruby_package: "other.pkg_name"))).to eq(["Other", "PkgName"])
    end

    it "defines no module for a file without a package" do
      expect(described_class.package_modules(file(package: ""))).to eq([])
    end
  end

  describe ".rubify_constant" do
    it { expect(described_class.rubify_constant("lowerCase")).to eq("LowerCase") }
    it { expect(described_class.rubify_constant("Upper")).to eq("Upper") }
    it { expect(described_class.rubify_constant("_hidden")).to eq("PB__hidden") }
  end

  describe ".underscore" do
    {
      "Greet" => "greet",
      "GetHTTPStatus" => "get_http_status",
      "ListV2Items" => "list_v2_items",
      "already_snake" => "already_snake",
    }.each do |name, expected|
      it("maps #{name} to #{expected}") { expect(described_class.underscore(name)).to eq(expected) }
    end
  end
end
