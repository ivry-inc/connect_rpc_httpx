# frozen_string_literal: true

require_relative "../spec_helper"
require "rbs"

RSpec.describe(ProtocGenConnectRuby::Generator) do
  def generate(*files, parameter: "")
    described_class.new(code_generator_request(*files, parameter:)).run
  end

  # Set UPDATE_GOLDEN=1 to rewrite the expected files after an intended change.
  shared_examples "golden output" do |proto|
    it "matches the checked-in output for #{proto}" do
      response = generate(proto)
      expect(response.error).to eq("")

      response.file.each do |file|
        path = File.join(ProtocHelper::FIXTURES, "gen", file.name)
        if ENV["UPDATE_GOLDEN"]
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, file.content)
        end
        expect(file.content).to eq(File.read(path)), "#{file.name} differs from #{path}"
      end
      expect(response.file.map(&:name)).to contain_exactly(
        ProtocGenConnectRuby::Naming.output_path(proto, ".rb"),
        ProtocGenConnectRuby::Naming.output_path(proto, ".rbs"),
      )
    end
  end

  include_examples "golden output", "acme/greet/v1/greet.proto"
  include_examples "golden output", "acme/shapes/v1/shapes.proto"

  it "writes RBS that parses" do
    generate("acme/greet/v1/greet.proto", "acme/shapes/v1/shapes.proto").file.each do |file|
      next unless file.name.end_with?(".rbs")

      expect { RBS::Parser.parse_signature(file.content) }.not_to raise_error
    end
  end

  it "writes nothing for a file without services" do
    expect(generate("acme/empty/v1/messages.proto").file).to be_empty
  end

  it "declares support for proto3 optional and editions" do
    response = generate("acme/greet/v1/greet.proto")

    expect(response.supported_features).to eq(described_class::SUPPORTED_FEATURES)
    expect(response.maximum_edition).to eq(Google::Protobuf::Edition::EDITION_2024)
  end

  it "reports an unknown parameter as an error" do
    expect(generate("acme/greet/v1/greet.proto", parameter: "bogus").error).to eq("unknown parameter: bogus")
  end

  # A request for a.proto, declaring message M and service S with an RPC per name.
  def rpcs_request(*names)
    Google::Protobuf::Compiler::CodeGeneratorRequest.new(
      file_to_generate: ["a.proto"],
      proto_file: [
        Google::Protobuf::FileDescriptorProto.new(
          name: "a.proto",
          package: "a",
          message_type: [Google::Protobuf::DescriptorProto.new(name: "M")],
          service: [
            Google::Protobuf::ServiceDescriptorProto.new(
              name: "S",
              method: names.map { |name| Google::Protobuf::MethodDescriptorProto.new(name:, input_type: ".a.M", output_type: ".a.M") },
            ),
          ],
        ),
      ],
    )
  end

  it "reports two RPCs that map to the same Ruby method" do
    expect(described_class.new(rpcs_request("GetFoo", "Get_Foo")).run.error).to eq("a.S: GetFoo and Get_Foo both map to the Ruby method get_foo")
  end

  it "suffixes RPCs that would override a private method of the client or of Object" do
    ruby = described_class.new(rpcs_request("Get", "Initialize", "Raise")).run.file.first.content

    expect(ruby.scan(/^ *def (\w+)/).flatten).to eq(["get_", "initialize_", "raise_"])
  end
end
