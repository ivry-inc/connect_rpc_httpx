# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe("generated signatures") do
  root = File.expand_path("../../..", __dir__)
  usage = File.join(ProtocHelper::FIXTURES, "steep", "usage.rb")

  # Steep loads signatures only from under its project directory, so everything is copied there.
  def steep_project(dir, root)
    response = ProtocGenConnectRuby::Generator.new(
      code_generator_request("acme/greet/v1/greet.proto", "acme/shapes/v1/shapes.proto"),
    ).run
    response.file.each do |file|
      next unless file.name.end_with?(".rbs")

      path = File.join(dir, "sig", "gen", file.name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, file.content)
    end
    FileUtils.cp_r(File.join(ProtocHelper::FIXTURES, "sig"), File.join(dir, "sig", "messages"))
    FileUtils.cp_r(File.join(root, "connect_rpc_httpx", "sig"), File.join(dir, "sig", "runtime"))
    File.write(File.join(dir, "Steepfile"), <<~STEEPFILE)
      target :usage do
        signature "sig"
        check "usage.rb"
        collection_config #{File.join(root, "rbs_collection.yaml").inspect}
        library "forwardable", "openssl", "json", "uri"
      end
    STEEPFILE
  end

  it "accept every way of passing a request and reject wrong fields" do
    output = Dir.mktmpdir do |dir|
      steep_project(dir, root)
      FileUtils.cp(usage, File.join(dir, "usage.rb"))
      out, _status = Open3.capture2e(Gem.ruby, Gem.bin_path("steep", "steep"), "check", chdir: dir)
      out
    end

    expected = File.readlines(usage).each_with_index.filter_map { |line, i| i + 1 if line.end_with?("# error\n") }
    reported = output.scan(/^usage\.rb:(\d+):\d+: \[(?:error|warning)\]/).flatten.map(&:to_i).uniq
    expect(reported).to eq(expected), output
  end
end
