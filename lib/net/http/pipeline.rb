require 'net/http'

##
# An HTTP/1.1 pipelining implementation atop Net::HTTP.  Currently this is not
# compliant with RFC 2616 8.1.2.2.
#
# Pipeline allows pou to create a bunch of requests then pipeline them to an
# HTTP/1.1 server.
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

  VERSION = '0.0'

  ##
  # Pipeline error class

  class Error < RuntimeError
  end

  ##
  # Pipelines +requests+ to the HTTP server yielding responses if a block is
  # given.  Returns all responses recieved.
  #
  # Raises an exception if the connection is not pipelining-capable or if the
  # HTTP session has not been started.

  def pipeline *requests
    raise Error, 'pipelining requires HTTP/1.1 or newer' unless
      @curr_http_version >= '1.1'
    raise Error, 'Net::HTTP not started' unless started?

    requests.each do |req|
      begin_transport req
      req.exec @socket, @curr_http_version, edit_path(req.path)
    end

    responses = []

    requests.each do |req|
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

  ##
  # Checks for an connection close header

  def pipeline_keep_alive? res
    not res.connection_close?
  end

end

class Net::HTTP

  ##
  # Adds pipeline support to Net::HTTP

  include Pipeline

end

