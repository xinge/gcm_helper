module GcmHelper
  class MulticastResult
    attr_accessor :success, :failure, :canonical_ids, :multicast_id, :results, :retry_multicast_ids

    def initialize(args)
      [:success, :failure, :canonical_ids, :multicast_id].each do |attr|
        instance_variable_set("@#{attr}", args[attr]) if (args.key?(attr))
      end
      instance_variable_set("@results", [])
      instance_variable_set("@retry_multicast_ids", [])
    end

    def inspect
      [:success, :failure, :canonical_ids, :multicast_id, :results, :retry_multicast_ids].inject({ }) do |h, attr|
        h[attr] = instance_variable_get("@#{attr}")
        h
      end
    end

    def to_s
      "MulticastResult #{self.inspect.to_s}"
    end

  end
end