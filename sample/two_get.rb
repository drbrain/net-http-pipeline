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
