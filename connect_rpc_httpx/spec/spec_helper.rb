# frozen_string_literal: true

require "connect_rpc_httpx"
require "google/protobuf/descriptor_pb"
require "webmock/rspec"
require "httpx/adapters/webmock"

module TestMessages
  file = Google::Protobuf::FileDescriptorProto.new(
    name: "connect_rpc_httpx/test/echo.proto",
    package: "connect_rpc_httpx.test",
    syntax: "proto3",
    message_type: [
      Google::Protobuf::DescriptorProto.new(
        name: "EchoRequest",
        field: [Google::Protobuf::FieldDescriptorProto.new(name: "text", number: 1, type: :TYPE_STRING, label: :LABEL_OPTIONAL, json_name: "text")],
      ),
      Google::Protobuf::DescriptorProto.new(
        name: "EchoResponse",
        field: [Google::Protobuf::FieldDescriptorProto.new(name: "count", number: 1, type: :TYPE_INT64, label: :LABEL_OPTIONAL, json_name: "count")],
      ),
    ],
  )
  Google::Protobuf::DescriptorPool.generated_pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file))

  EchoRequest = Google::Protobuf::DescriptorPool.generated_pool.lookup("connect_rpc_httpx.test.EchoRequest").msgclass
  EchoResponse = Google::Protobuf::DescriptorPool.generated_pool.lookup("connect_rpc_httpx.test.EchoResponse").msgclass
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
