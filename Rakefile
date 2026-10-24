# frozen_string_literal: true

require "bundler/gem_helper"
require "rspec/core/rake_task"

GEMS = ["connect_rpc_httpx", "protoc_gen_connect_ruby"].freeze

# `rake connect_rpc_httpx:release` and so on, one namespace per gem directory.
GEMS.each do |name|
  namespace(name) { Bundler::GemHelper.install_tasks(dir: name, name:) }
end

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "{#{GEMS.join(",")}}/spec/**/*_spec.rb"
end

# No `rbs validate`: it checks every library signature, and httpx ships signatures for plugins
# whose optional gems are not installed. steep check validates this project's signatures.
desc "Regenerate inline RBS signatures under each gem's sig/generated"
task :rbs do
  GEMS.each do |name|
    Dir.chdir(name) { sh "rbs-inline --output=sig/generated lib" }
  end
end

desc "Type check both gems against their RBS signatures"
task steep: :rbs do
  sh "steep check"
end

desc "Generate YARD documentation into doc/yard"
task :yard do
  sh "yard doc"
end

desc "Generate RDoc documentation into doc/rdoc/<gem>"
task :rdoc do
  GEMS.each do |name|
    # RDoc picks up RBS signatures from the sig/ directory under its working directory.
    Dir.chdir(name) { sh "rdoc --quiet --output ../doc/rdoc/#{name} --main README.md lib README.md" }
  end
end

task default: [:spec, :steep]
