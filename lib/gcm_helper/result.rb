module GcmHelper
  class Result
    attr_accessor :message_id, :canonical_registration_id, :error_code

    def initialize(args)
      [:message_id, :canonical_registration_id, :error_code].each do |attr|
        instance_variable_set("@#{attr}", args[attr]) if (args.key?(attr))
      end
    end

    def inspect
      [:message_id, :canonical_registration_id, :error_code].inject({ }) do |h, attr|
        h[attr] = instance_variable_get("@#{attr}")
        h
      end
    end

    def to_s
      "Result #{self.inspect.to_s}"
    end
  end
end