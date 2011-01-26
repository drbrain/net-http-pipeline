require 'minitest/autorun'
require 'net/http/pipeline'
require 'stringio'

class TestNetHttpPipeline < MiniTest::Unit::TestCase

  include Net::HTTP::Pipeline

  def setup
    @curr_http_version = '1.1'
    @started = true

    @get1 = Net::HTTP::Get.new '/'
    @get2 = Net::HTTP::Get.new '/'
    @get3 = Net::HTTP::Get.new '/'
    @post = Net::HTTP::Post.new '/'
  end

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

    def read bytes, dest = '', ignored = nil
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

  attr_writer :started

  def D(*) end

  def begin_transport req
  end

  def edit_path path
    path
  end

  def http_get
    get = []
    get << 'GET / HTTP/1.1'
    get << 'Accept: */*'
    get << 'User-Agent: Ruby' if RUBY_VERSION > '1.9'
    get.push nil, nil

    get.join "\r\n"
  end

  def http_post
    get = []
    get << 'POST / HTTP/1.1'
    get << 'Accept: */*'
    get << 'User-Agent: Ruby' if RUBY_VERSION > '1.9'
    get.push nil, nil

    get.join "\r\n"
  end

  def http_response body, *extra_header
    http_response = []
    http_response << 'HTTP/1.1 200 OK'
    http_response << "Content-Length: #{body.bytesize}"
    http_response.push(*extra_header)
    http_response.push nil, nil # Array chomps on #join

    http_response.join("\r\n") << body
  end

  def request req
    req.exec @socket, @curr_http_version, edit_path(req.path)

    res = Net::HTTPResponse.read_new @socket

    res.reading_body @socket, req.response_body_permitted? do
      yield res if block_given?
    end

    @curr_http_version = res.http_version

    @socket.close unless pipeline_keep_alive? res

    res
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

  # tests start

  def test_idempotent_eh
    http = Net::HTTP.new 'localhost'

    assert http.idempotent? Net::HTTP::Delete.new '/'
    assert http.idempotent? Net::HTTP::Get.new '/'
    assert http.idempotent? Net::HTTP::Head.new '/'
    assert http.idempotent? Net::HTTP::Options.new '/'
    assert http.idempotent? Net::HTTP::Put.new '/'
    assert http.idempotent? Net::HTTP::Trace.new '/'

    refute http.idempotent? Net::HTTP::Post.new '/'
  end

  def test_pipeline
    @socket = Buffer.new
    @socket.read_io.write http_response('Worked 1!')
    @socket.read_io.write http_response('Worked 2!')
    @socket.start

    requests = [@get1, @get2]

    responses = pipeline requests

    @socket.finish

    expected = http_get * 2

    assert_equal expected, @socket.write_io.read
    refute @socket.closed?

    assert_equal 'Worked 1!', responses.first.body
    assert_equal 'Worked 2!', responses.last.body

    assert_empty requests
  end

  def test_pipeline_http_1_0
    @curr_http_version = '1.0'

    @socket = Buffer.new
    @socket.read_io.write http_response('Worked 1!', 'Connection: close')
    @socket.start

    e = assert_raises Net::HTTP::Pipeline::VersionError do
      pipeline [@get1, @get2]
    end

    assert_equal [@get1, @get2], e.requests
    assert_empty e.responses
  end

  def test_pipeline_non_idempotent
    @socket = Buffer.new
    @socket.read_io.write http_response('Worked 1!')
    @socket.read_io.write http_response('Worked 2!')
    @socket.read_io.write http_response('Worked 3!')
    @socket.read_io.write http_response('Worked 4!')
    @socket.start

    responses = pipeline [@get1, @get2, @post, @get3]

    @socket.finish

    expected = ''
    expected << http_get * 2
    expected << http_post
    expected << http_get

    assert_equal expected, @socket.write_io.read
    refute @socket.closed?

    assert_equal 'Worked 1!', responses.shift.body
    assert_equal 'Worked 2!', responses.shift.body
    assert_equal 'Worked 3!', responses.shift.body
    assert_equal 'Worked 4!', responses.shift.body

    assert responses.empty?
  end

  def test_pipeline_non_persistent
    @persistent = false

    @socket = Buffer.new
    @socket.read_io.write http_response('Worked 1!', 'Connection: close')
    @socket.start

    e = assert_raises Net::HTTP::Pipeline::PersistenceError do
      pipeline [@get1, @get2]
    end

    assert_equal [@get2], e.requests
    assert_equal 1, e.responses.length
    assert_equal 'Worked 1!', e.responses.first.body
  end

  def test_pipeline_not_started
    @started = false

    e = assert_raises Net::HTTP::Pipeline::Error do
      pipeline []
    end

    assert_equal 'Net::HTTP not started', e.message
  end

  # end #pipeline tests

  def test_pipeline_check
    @socket = Buffer.new
    @socket.read_io.write <<-HTTP_1_0
HTTP/1.1 200 OK\r
Content-Length: 9\r
\r
Worked 1!
    HTTP_1_0
    @socket.start

    requests = [@get1, @get2]
    responses = []

    pipeline_check requests, responses

    assert_equal [@get2], requests
    assert_equal 1, responses.length
    assert_equal 'Worked 1!', responses.first.body
    assert pipelining
  end

  def test_pipeline_check_http_1_0
    @socket = Buffer.new
    @socket.read_io.write <<-HTTP_1_0
HTTP/1.0 200 OK\r
Content-Length: 9\r
\r
Worked 1!
    HTTP_1_0
    @socket.start

    e = assert_raises Net::HTTP::Pipeline::VersionError do
      pipeline_check [@get1, @get2], []
    end

    assert_equal [@get2], e.requests
    assert_equal 1, e.responses.length
    assert_equal 'Worked 1!', e.responses.first.body
    refute pipelining
  end

  def test_pipeline_check_non_persistent
    @socket = Buffer.new
    @socket.read_io.write http_response('Worked 1!', 'Connection: close')
    @socket.start

    e = assert_raises Net::HTTP::Pipeline::PersistenceError do
      pipeline_check [@get1, @get2], []
    end

    assert_equal [@get2], e.requests
    assert_equal 1, e.responses.length
    assert_equal 'Worked 1!', e.responses.first.body
    refute pipelining
  end

  def test_pipeline_check_pipelining
    self.pipelining = true
    @socket = Buffer.new
    @socket.start

    requests = [@get1, @get2]
    responses = []

    pipeline_check requests, responses

    assert_equal [@get1, @get2], requests
    assert_empty responses
    assert pipelining
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

  def test_pipeline_send
    @socket = Buffer.new
    @socket.start

    requests = [@get1, @get2, @post, @get3]

    in_flight = pipeline_send requests

    @socket.finish

    assert_equal [@get1, @get2], in_flight
    assert_equal [@post, @get3], requests

    expected = ''
    expected << http_get * 2

    assert_equal expected, @socket.write_io.read
  end

  def test_pipeline_send_non_idempotent
    @socket = Buffer.new
    @socket.start

    requests = [@post, @get3]

    in_flight = pipeline_send requests

    @socket.finish

    assert_equal [@post], in_flight
    assert_equal [@get3], requests

    expected = http_post

    assert_equal expected, @socket.write_io.read
  end

end

