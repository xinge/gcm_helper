module GcmHelper
  class Sender
    UTF8 = "UTF-8"
    BACKOFF_INITIAL_DELAY = 1000
    MAX_BACKOFF_DELAY = 1024000

    attr_accessor :logger

    def initialize(key)
      @key=self.class.nonNull(key)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::WARN
    end

    def self.nonNull(argument)
      raise ArgumentError, "argument cannot be null" if argument.nil?
      argument
    end

    def self.newBody(name, value)
      nonNull(name) << '=' << nonNull(value)
    end

    def self.addParameter(body, name, value)
      nonNull(body) << '&' << nonNull(name) << '=' << nonNull(value)
    end

    # @param [GcmHelper::Message] message
    # @param [String] registration_id
    # @param [Integer] retries
    # @return [Result]
    def sendWithRetry(message, registration_id, retries)
      attempt = 0
      result = nil
      backoff = BACKOFF_INITIAL_DELAY
      tryAgain = false
      begin
        attempt += 1
        logger.info("Sender") {"Attempt ##{attempt} to send message #{message} to regIds #{registration_id}"}
        result = sendNoRetry(message, registration_id)
        tryAgain = result.nil? && attempt <= retries
        if tryAgain
          sleepTime = backoff / 2 + rand(backoff)
          sleep(sleepTime / 1000)
          backoff *= 2 if (2 * backoff < MAX_BACKOFF_DELAY)
        end
      end while (tryAgain)

      raise IOError, "Could not send message after #{attempt} attempts" if result.nil?

      result
    end

    # @param [GcmHelper::Message] message
    # @param [String] registration_id
    # @return [Result]
    def sendNoRetry(message, registration_id)
      body = self.class.newBody(PARAM_REGISTRATION_ID, registration_id)
      self.class.addParameter(body, PARAM_DELAY_WHILE_IDLE, message.delay_while_idle? ? '1':'0') unless message.delay_while_idle.nil?
      self.class.addParameter(body, PARAM_COLLAPSE_KEY, message.collapse_key) unless message.collapse_key.nil?
      self.class.addParameter(body, PARAM_TIME_TO_LIVE, message.time_to_live.to_s) unless message.time_to_live.nil?
      message.data.each { |key, value|
        self.class.addParameter(body, PARAM_PAYLOAD_PREFIX+key, URI::encode(value.force_encoding(UTF8)))
      } unless message.data.nil?
      logger.info("Sender") {"Request body: #{body}"}
      resp = http_post(GCM_SEND_ENDPOINT, body)

      if resp.code.eql? "503"
        logger.warn("Sender") {"GCM service is unavailable"}
        return nil
      end

      raise Exceptions::InvalidRequestException, Exceptions::InvalidRequestException.get_message(resp.code) unless resp.code.eql? '200'

      resp_body = {}
      resp.body.each_line {|line|
        key, value = line.strip.split('=', 2)
        resp_body[key] = value
      }

      if resp_body.has_key?(TOKEN_MESSAGE_ID)
        result=Result.new(message_id: resp_body[TOKEN_MESSAGE_ID])
        result.canonical_registration_id = resp_body[TOKEN_CANONICAL_REG_ID] if resp_body.has_key?(TOKEN_CANONICAL_REG_ID)
        logger.info("Sender") {"Message created successfully (#{result})"}
      elsif resp_body.has_key?(TOKEN_ERROR)
        result=Result.new(error_code: resp_body[TOKEN_ERROR])
      else
        raise IOError, "Received invalid response from GCM: #{resp.body}"; return nil
      end

      result
    end


    # @param [String] url
    # @param [String] body
    # @param [String] content_type
    def http_post(url, body, content_type="application/x-www-form-urlencoded;charset=UTF-8")
      self.class.nonNull(url)
      self.class.nonNull(body)
      logger.warn("Sender") {"URL does not use https: #{url}"} unless url.start_with?("https://")
      logger.debug("Sender") {"Sending POST to #{url}"}
      logger.debug("Sender") {"POST body: #{body}"}

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl= true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      headers = {
        "Content-Type" => content_type,
        "Authorization" => "key=#{@key}" ,
        "Content-length" => "#{body.length}"
      }
      http.start
      http.post(uri.path, body, headers)

    end


#Endpoint for sending messages.
  GCM_SEND_ENDPOINT = "https://android.googleapis.com/gcm/send"

#HTTP parameter for registration id.
  PARAM_REGISTRATION_ID = "registration_id"

#HTTP parameter for collapse key.
  PARAM_COLLAPSE_KEY = "collapse_key"

#HTTP parameter for delaying the message delivery if the device is idle.
  PARAM_DELAY_WHILE_IDLE = "delay_while_idle"

#Prefix to HTTP parameter used to pass key-values in the message payload.
  PARAM_PAYLOAD_PREFIX = "data."

#Prefix to HTTP parameter used to set the message time-to-live.
  PARAM_TIME_TO_LIVE = "time_to_live"

#Too many messages sent by the sender. Retry after a while.
  ERROR_QUOTA_EXCEEDED = "QuotaExceeded"

#Too many messages sent by the sender to a specific device.
#Retry after a while.
  ERROR_DEVICE_QUOTA_EXCEEDED = "DeviceQuotaExceeded"

#Missing registration_id.
#Sender should always add the registration_id to the request.
  ERROR_MISSING_REGISTRATION = "MissingRegistration"

#Bad registration_id. Sender should remove this registration_id.
  ERROR_INVALID_REGISTRATION = "InvalidRegistration"

#The sender_id contained in the registration_id does not match the
#sender_id used to register with the GCM servers.
  ERROR_MISMATCH_SENDER_ID = "MismatchSenderId"

#The user has uninstalled the application or turned off notifications.
#Sender should stop sending messages to this device and delete the
#registration_id. The client needs to re-register with the GCM servers to
#receive notifications again.
  ERROR_NOT_REGISTERED = "NotRegistered"

#The payload of the message is too big, see the limitations.
#Reduce the size of the message.
  ERROR_MESSAGE_TOO_BIG = "MessageTooBig"

#Collapse key is required. Include collapse key in the request.
  ERROR_MISSING_COLLAPSE_KEY = "MissingCollapseKey"

#Used to indicate that a particular message could not be sent because
#the GCM servers were not available. Used only on JSON requests, as in
#plain text requests unavailability is indicated by a 503 response.
  ERROR_UNAVAILABLE = "Unavailable"

#Token returned by GCM when a message was successfully sent.
  TOKEN_MESSAGE_ID = "id"

#Token returned by GCM when the requested registration id has a canonical
#value.
  TOKEN_CANONICAL_REG_ID = "registration_id"

#Token returned by GCM when there was an error sending a message.
  TOKEN_ERROR = "Error"

#JSON-only field representing the registration ids.
  JSON_REGISTRATION_IDS = "registration_ids"

#JSON-only field representing the payload data.
  JSON_PAYLOAD = "data"

#JSON-only field representing the number of successful messages.
  JSON_SUCCESS = "success"

#JSON-only field representing the number of failed messages.
  JSON_FAILURE = "failure"

#JSON-only field representing the number of messages with a canonical
#registration id.
  JSON_CANONICAL_IDS = "canonical_ids"

#JSON-only field representing the id of the multicast request.
  JSON_MULTICAST_ID = "multicast_id"

#JSON-only field representing the result of each individual request.
  JSON_RESULTS = "results"

#JSON-only field representing the error field of an individual request.
  JSON_ERROR = "error"

#JSON-only field sent by GCM when a message was successfully sent.
  JSON_MESSAGE_ID = "message_id"

  end
end