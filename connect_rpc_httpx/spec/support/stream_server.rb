# frozen_string_literal: true

require "socket"

# A keep-alive HTTP/1.1 server for streaming specs, which webmock cannot stand in for. Each
# request is answered by the block with [status, headers, chunks]; chunks go out as separate
# chunked-encoding chunks.
class StreamServer
  Request = Data.define(:verb, :path, :headers, :body)

  attr_reader :requests, :connections

  def initialize(&handler)
    @handler = handler
    @requests = Thread::Queue.new
    @connections = 0
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { accept_loop }
  end

  def url = "http://127.0.0.1:#{@server.addr[1]}"

  def stop
    @thread.kill
    @server.close
  end

  private def accept_loop
    loop do
      socket = @server.accept
      @connections += 1
      Thread.new(socket) { |s| serve(s) }
    end
  end

  private def serve(socket)
    while (request = read_request(socket))
      @requests << request
      status, headers, chunks = @handler.call(request)
      socket.write("HTTP/1.1 #{status} X\r\ntransfer-encoding: chunked\r\n")
      headers.each { |name, value| socket.write("#{name}: #{value}\r\n") }
      socket.write("\r\n")
      chunks.each do |chunk|
        socket.write("#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n")
        socket.flush
      end
      socket.write("0\r\n\r\n")
      socket.flush
    end
  rescue IOError, SystemCallError
    nil
  ensure
    socket.close
  end

  private def read_request(socket)
    head = socket.gets("\r\n\r\n") or return
    verb, path = head.lines.first.split
    headers = head.lines.drop(1).filter_map do |line|
      name, value = line.chomp.split(": ", 2)
      [name.downcase, value] if value
    end.to_h
    body = if headers["transfer-encoding"] == "chunked"
      read_chunked(socket)
    else
      socket.read(headers.fetch("content-length", "0").to_i)
    end
    Request.new(verb:, path:, headers:, body: body.b)
  end

  private def read_chunked(socket)
    body = +""
    loop do
      size = socket.gets("\r\n").to_i(16)
      chunk = socket.read(size + 2).byteslice(0, size)
      break if size.zero?

      body << chunk
    end
    body
  end
end
