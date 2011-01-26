require 'net/http'

##
# An HTTP/1.1 pipelining implementation atop Net::HTTP.  Currently this is not
# compliant with RFC 2616 8.1.2.2.
#
# Pipeline allows you to create a bunch of requests then send them all to an
# HTTP/1.1 server without waiting for responses.  The server will return HTTP
# responses in-order.
#
# Net::HTTP::Pipeline does not assume the server is pipelining-capable.  If
# you know it is you can set Net::HTTP#persistent to true.
#
# = Example
#
#   require 'net/http/pipeline'
#
#   Net::HTTP.start 'localhost' do |http|
#     req1 = Net::HTTP::Get.new '/'
#     req2 = Net::HTTP::Get.new '/'
#
#     http.pipeline req1, req2 do |res|
#       puts res.code
#       puts res.body[0..60].inspect
#       puts
#     end
#   end

module Net::HTTP::Pipeline

  ##
  # The version of net-http-pipeline you are using

  VERSION = '1.0'

  ##
  # Pipeline error class

  class Error < RuntimeError

    ##
    # Remaining requests that have not been sent to the HTTP server

    attr_reader :requests

    ##
    # Retrieved responses up to the error point

    attr_reader :responses

    ##
    # Creates a new Error with +message+, a list of +requests+ that have not
    # been sent to the server and a list of +responses+ that have been
    # retrieved from the server.

    def initialize message, requests, responses
      super message

      @requests = requests
      @responses = responses
    end

  end

  ##
  # Raised when an invalid version is given

  class VersionError < Error
    ##
    # Creates a new VersionError with +requests+ and +responses+ a list of
    # +requests+ that have not been sent to the server and a list of
    # +responses+ that have been retrieved from the server.

    def initialize requests, responses
      super 'HTTP/1.1 or newer required', requests, responses
    end
  end

  ##
  # Raised when the server appears to not support persistent connections

  class PersistenceError < Error
    ##
    # Creates a new PersistenceError with +requests+ and +responses+ a list of
    # +requests+ that have not been sent to the server and a list of
    # +responses+ that have been retrieved from the server.

    def initialize requests, responses
      super 'HTTP/1.1 or newer required', requests, responses
    end
  end

  ##
  # Persistence accessor.
  #
  # Pipeline assumes servers will not make persistent connections by default.
  # The first request is not pipelined while Pipeline ensures that the server
  # is HTTP/1.1 or newer and defaults to persistent connections.
  #
  # If you know the server is both HTTP/1.1 and defaults to persistent
  # connections you can set this to true when you create the Net::HTTP object.

  attr_accessor :persistent

  ##
  # Is +req+ idempotent according to RFC 2616?

  def idempotent? req
    case req
    when Net::HTTP::Delete, Net::HTTP::Get, Net::HTTP::Head,
         Net::HTTP::Options, Net::HTTP::Put, Net::HTTP::Trace then
      true
    end
  end

  ##
  # Pipelines +requests+ to the HTTP server yielding responses if a block is
  # given.  Returns all responses recieved.
  #
  # Raises an exception if the connection is not pipelining-capable or if the
  # HTTP session has not been started.

  def pipeline requests
    responses = []

    raise Error.new('Net::HTTP not started', requests, responses) unless
      started?

    raise VersionError.new(requests, responses) if '1.1' > @curr_http_version

    @persistent = false unless instance_variable_defined? :@persistent

    pipeline_check requests, responses unless @persistent

    until requests.empty? do
      in_flight = pipeline_send requests

      pipeline_receive in_flight, responses
    end

    responses
  end

  def pipeline_check requests, responses
    request requests.shift do |res|
      responses << res

      yield res if block_given?

      @persistent = pipeline_keep_alive? res
    end

    return if responses if requests.empty?

    if '1.1' > @curr_http_version then
      raise VersionError.new(requests, responses)
    elsif not @persistent then
      raise PersistenceError.new(requests, responses)
    end
  end

  ##
  # Updates the HTTP version and ensures the connection has keep-alive.

  def pipeline_end_transport res
    @curr_http_version = res.http_version

    if @socket.closed? then
      D 'Conn socket closed on pipeline'
    elsif pipeline_keep_alive? res then
      D 'Conn pipeline keep-alive'
    else
      D 'Conn close on pipeline'
      @socket.close
    end
  end

  if Net::HTTPResponse.allocate.respond_to? :connection_close? then
    ##
    # Checks for an connection close header

    def pipeline_keep_alive? res
      not res.connection_close?
    end
  else
    def pipeline_keep_alive? res
      not res['connection'].to_s =~ /close/i
    end
  end

  ##
  # Receives HTTP responses for +in_flight+ requests and adds them to
  # +responses+

  def pipeline_receive in_flight, responses
    in_flight.each do |req|
      begin
        res = Net::HTTPResponse.read_new @socket
      end while res.kind_of? Net::HTTPContinue

      res.reading_body @socket, req.response_body_permitted? do
        responses << res
        yield res if block_given?
      end

      pipeline_end_transport res
    end

    responses
  end

  ##
  # Sends +requests+ to the HTTP server and removes them from the +requests+
  # list.  Returns the requests that have been pipelined and are in-flight.
  #
  # If a non-idempotent request is first in +requests+ it will be sent and no
  # further requests will be pipelined.
  #
  # If a non-idempotent request is encountered after an idempotent request it
  # will not be sent.

  def pipeline_send requests
    in_flight = []

    while req = requests.shift do
      idempotent = idempotent? req

      unless idempotent or in_flight.empty? then
        requests.unshift req
        break
      end

      begin_transport req
      req.exec @socket, @curr_http_version, edit_path(req.path)
      in_flight << req

      break unless idempotent
    end

    in_flight
  end

end

class Net::HTTP

  ##
  # Adds pipeline support to Net::HTTP

  include Pipeline

end

