module GcmHelper
  class Result
    attr_accessor :message_id, :canonical_registration_id, :error_code

    def initialize(args)
      instance_variable_set("@message_id", args[:message_id]) if args.key?(:message_id)
      instance_variable_set("@error_code", args[:error_code]) if args.key?(:error_code)
    end

    def to_s
      str = "["
      str << " messageId=#{message_id}" unless message_id.nil? || message_id.empty?
      str << " canonicalRegistrationId=#{canonical_registration_id}" unless canonical_registration_id.nil? || canonical_registration_id.empty?
      str << " errorCode=#{error_code}" unless error_code.nil? || error_code.empty?
      str << " ]"
      str
    end
  end
end