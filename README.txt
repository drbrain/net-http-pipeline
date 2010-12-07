= net-http-pipeline

* http://seattlerb.rubyforge.org/net-http-pipeline
* http://github.com/drbrain/net-http-pipeline

== DESCRIPTION:

An HTTP/1.1 pipelining implementation atop Net::HTTP.  This is an experimental
proof of concept.

== FEATURES/PROBLEMS:

* Provides HTTP/1.1 pipelining
* Does not implement request wrangling per RFC 2616 8.1.2.2
* Does not handle errors
* May not work on Ruby 1.8, untested

== SYNOPSIS:

  require 'net/http/pipeline'

  Net::HTTP.start 'localhost' do |http|
    req1 = Net::HTTP::Get.new '/'
    req2 = Net::HTTP::Get.new '/'

    http.pipeline req1, req2 do |res|
      puts res.code
      puts res.body[0..60].inspect
      puts
    end
  end

== INSTALL:

  gem install net-http-pipeline

== LICENSE:

(The MIT License)

Copyright (c) 2010 Eric Hodel

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
