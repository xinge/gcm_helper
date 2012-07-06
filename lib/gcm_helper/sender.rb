module GcmHelper
  class Sender

    attr_accessor :logger

    def initialize(key)
      @key=self.class.non_null(key)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::DEBUG
    end

    def self.non_null(argument)
      raise ArgumentError, "argument cannot be null" if argument.nil?
      argument
    end

    def self.new_body(name, value)
      "#{non_null(name)}=#{non_null(value)}"
    end

    def self.add_parameter(body, name, value)
      non_null(body) << "&#{non_null(name)}=#{non_null(value)}"
    end

    # @param [GcmHelper::Message] message
    # @param [String] registration_id
    # @param [Integer] retries
    # @return [Result]
    def send_with_retry(message, registration_id, retries)
      attempt = 0
      result = nil
      backoff = BACKOFF_INITIAL_DELAY
      tryAgain = false
      begin
        attempt += 1
        logger.info("Sender") {"Attempt ##{attempt} to send message #{message} to regIds #{registration_id}"}
        result = send_no_retry(message, registration_id)
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
    def send_no_retry(message, registration_id)
      body = self.class.new_body(PARAM_REGISTRATION_ID, registration_id)
      self.class.add_parameter(body, PARAM_DELAY_WHILE_IDLE, message.delay_while_idle? ? '1':'0') unless message.delay_while_idle.nil?
      self.class.add_parameter(body, PARAM_COLLAPSE_KEY, message.collapse_key) unless message.collapse_key.nil?
      self.class.add_parameter(body, PARAM_TIME_TO_LIVE, message.time_to_live.to_s) unless message.time_to_live.nil?
      message.data.each { |key, value|
        self.class.add_parameter(body, PARAM_PAYLOAD_PREFIX+key, URI::encode(value.force_encoding('UTF-8')))
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

    # @param [GcmHelper::Message] message
    # @param [Array] registration_ids
    # @param [Integer] retries
    # @return [GcmHelper::MulticastResult]
    def multicast_with_retry(message, registration_ids, retries)
      attempt = 0
      multicast_result = nil
      backoff = BACKOFF_INITIAL_DELAY
      #Map of results by registration id, it will be updated after each attempt to send the messages
      results = {}
      unsent_reg_ids = Array(registration_ids)
      tryAgain = false
      multicast_ids = []
      begin
        attempt += 1
        logger.debug("Sender") {"Attempt ##{attempt} to send message #{message} to regIds #{unsent_reg_ids}"}
        multicast_result= multicast_no_retry(message, registration_ids)
        multicast_id = multicast_result.multicast_id
        logger.debug("Sender") {"multicast_id on attempt ##{attempt}: #{multicast_id}"}
        multicast_ids << multicast_id
        unsent_reg_ids = update_status(unsent_reg_ids, results, multicast_result)

        tryAgain = !unsent_reg_ids.empty? && attempt <= retries

        if tryAgain
          sleepTime = backoff / 2 + rand(backoff)
          sleep(sleepTime / 1000)
          backoff *= 2 if (2 * backoff < MAX_BACKOFF_DELAY)
        end
      end while (tryAgain)

      # calculate summary
      success = 0
      failure = 0
      canonical_ids = 0
      results.each_value { |r|
        unless(r.message_id.nil?)
          success += 1
          canonical_ids +=1 unless r.canonical_registration_id.nil?
        else
          failure += 1
        end
      }
      # build a new object with the overall result
      multicast_id = multicast_ids.shift
      multicast_result = MulticastResult.new(success: success, failure: failure, canonical_ids: canonical_ids, multicast_id: multicast_id)
      # add results, in the same order as the input
      registration_ids.each {|reg_id|
        multicast_result.results << results[reg_id]
      }

      multicast_result

    end

    # @param [GcmHelper::Message] message
    # @param [Array] registration_ids
    # @return [GcmHelper::MulticastResult]
    def multicast_no_retry(message, registration_ids)
      raise ArgumentError, "registration_ids cannot be empty" if self.class.non_null(registration_ids).empty?

      json_request = Hash.new
      json_request[PARAM_TIME_TO_LIVE]=message.time_to_live unless message.time_to_live.nil?
      json_request[PARAM_COLLAPSE_KEY]=message.collapse_key unless message.collapse_key.nil?
      json_request[PARAM_DELAY_WHILE_IDLE]=message.delay_while_idle unless message.delay_while_idle.nil?
      json_request[JSON_REGISTRATION_IDS]= registration_ids
      json_request[JSON_PAYLOAD]= message.data unless message.data.empty?

      require "json"
      request_body = json_request.to_json
      logger.debug("Sender") {"JSON request: #{request_body}"}
      resp = http_post(GCM_SEND_ENDPOINT, request_body, "application/json")

      raise Exceptions::InvalidRequestException, Exceptions::InvalidRequestException.get_message(resp.code, resp.body) unless resp.code.eql? '200'

      json_response = JSON.parse(resp.body)

      success= Integer(json_response[JSON_SUCCESS])
      failure= Integer(json_response[JSON_FAILURE])
      canonical_ids= Integer(json_response[JSON_CANONICAL_IDS])
      multicast_id= Integer(json_response[JSON_MULTICAST_ID])

      multicast_result = MulticastResult.new(success: success, failure: failure, canonical_ids: canonical_ids, multicast_id: multicast_id)

      results = json_response[JSON_RESULTS]
      unless results.nil?
        results.each do |r|
          message_id= r[JSON_MESSAGE_ID]
          canonical_reg_id= r[TOKEN_CANONICAL_REG_ID]
          error= r[JSON_ERROR]
          result = Result.new(message_id: message_id, canonical_registration_id: canonical_reg_id, error_code: error)
          multicast_result.results << result
        end
      end

      multicast_result
    end

    # @param [String] url
    # @param [String] body
    # @param [String] content_type
    def http_post(url, body, content_type="application/x-www-form-urlencoded;charset=UTF-8")
      self.class.non_null(url)
      self.class.non_null(body)
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

    #Updates the status of the messages sent to devices and the list of devices that should be retried.
    # @param [Array] unsent_reg_ids
    # @param [Hash] all_results
    # @param [GcmHelper::MulticastResult] multicast_result
    def update_status(unsent_reg_ids, all_results, multicast_result)
      results = multicast_result.results
      raise RuntimeError, "Internal error: sizes do not match. currentResults: #{results}; unsentRegIds: #{unsent_reg_ids}" unless results.size==unsent_reg_ids.size
      new_unsent_reg_ids = []
      unsent_reg_ids.each_with_index {|reg_id, index|
        result = results[index]
        all_results[reg_id]= result
        new_unsent_reg_ids << reg_id unless (result.error_code.nil? || result.error.eql?(ERROR_UNAVAILABLE))
      }
      new_unsent_reg_ids
    end

#Initial delay before first retry, without jitter.
    BACKOFF_INITIAL_DELAY = 1000
#Maximum delay before a retry.
    MAX_BACKOFF_DELAY = 1024000

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