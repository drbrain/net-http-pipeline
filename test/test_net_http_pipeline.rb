require "test/unit"
require 'net/http/pipeline'
require 'stringio'

class TestNetHttpPipeline < Test::Unit::TestCase

  ##
  # Net::BufferedIO stub

  class Buffer
    attr_accessor :read_io, :write_io
    def initialize
      @read_io = StringIO.new
      @write_io = StringIO.new
      @closed = false
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end

    def finish
      @write_io.rewind
    end

    def read bytes, dest = '', ignored
      @read_io.read bytes, dest

      dest
    end

    def readline
      @read_io.readline.chomp "\r\n"
    end

    def readuntil terminator, ignored
      @read_io.gets terminator
    end

    def start
      @read_io.rewind
    end

    def write data
      @write_io.write data
    end
  end

  include Net::HTTP::Pipeline

  attr_writer :started

  def setup
    @curr_http_version = '1.1'
    @started = true
  end

  def D(*) end

  def begin_transport req
  end

  def edit_path path
    path
  end

  def http_response body, *extra_header
    http_response = []
    http_response << 'HTTP/1.1 200 OK'
    http_response << "Content-Length: #{body.bytesize}"
    http_response.push(*extra_header)
    http_response.push nil, nil # Array chomps on #join

    http_response.join("\r\n") << body
  end

  def response
    r = Net::HTTPResponse.allocate
    def r.http_version() Net::HTTP::HTTPVersion end
    def r.read_body() true end

    r.instance_variable_set :@header, {}
    def r.header() @header end
    r
  end

  def started?() @started end

  def test_pipeline
    @socket = Buffer.new

    @socket.read_io.write http_response('Worked 1!')
    @socket.read_io.write http_response('Worked 2!')

    req1 = Net::HTTP::Get.new '/'
    req2 = Net::HTTP::Get.new '/'

    @socket.start

    responses = pipeline req1, req2

    @socket.finish

    expected = <<-EXPECTED
GET / HTTP/1.1\r
Accept: */*\r
User-Agent: Ruby\r
\r
GET / HTTP/1.1\r
Accept: */*\r
User-Agent: Ruby\r
\r
    EXPECTED

    assert_equal expected, @socket.write_io.read
    refute @socket.closed?

    assert_equal 'Worked 1!', responses.first.body
    assert_equal 'Worked 2!', responses.last.body
  end

  def test_pipeline_connection_close
    @socket = Buffer.new

    @socket.read_io.write http_response('Worked 1!', 'Connection: close')

    req1 = Net::HTTP::Get.new '/'

    @socket.start

    responses = pipeline req1

    @socket.finish

    assert @socket.closed?
  end

  def test_pipeline_http_1_0
    @curr_http_version = '1.0'

    e = assert_raises Net::HTTP::Pipeline::Error do
      pipeline
    end

    assert_equal 'pipelining requires HTTP/1.1 or newer', e.message
  end

  def test_pipeline_not_started
    @started = false

    e = assert_raises Net::HTTP::Pipeline::Error do
      pipeline
    end

    assert_equal 'Net::HTTP not started', e.message
  end

  def test_pipeline_end_transport
    @curr_http_version = nil

    res = response

    @socket = StringIO.new

    pipeline_end_transport res

    refute @socket.closed?
    assert_equal '1.1', @curr_http_version
  end

  def test_pipeline_end_transport_no_keep_alive
    @curr_http_version = nil

    res = response
    res.header['connection'] = ['close']

    @socket = StringIO.new

    pipeline_end_transport res

    assert @socket.closed?
    assert_equal '1.1', @curr_http_version
  end

  def test_pipeline_keep_alive_eh
    res = response

    assert pipeline_keep_alive? res

    res.header['connection'] = ['close']

    refute pipeline_keep_alive? res
  end

end

