module Exceptions
  class InvalidRequestException < StandardError
    def self.get_message(status, description=nil)
      str = "HTTP Status Code: #{status}"
      str << "(#{description})" unless description.nil?
      str
    end
  end
end