module GcmHelper
  class Message

    attr_accessor :collapse_key, :delay_while_idle, :time_to_live, :data

    def initialize()
      @data={}
    end

    def delay_while_idle?
      !!delay_while_idle
    end

    def add_data(key, value)
      @data.store key, value
    end

    def inspect
      [:collapse_key, :delay_while_idle, :time_to_live, :data].inject({ }) do |h, attr|
        h[attr] = instance_variable_get("@#{attr}")
        h
      end
    end

    def to_s
      "Message #{self.inspect.to_s}"

      #str = "Message(";
      #str << "collapseKey=#{collapse_key}," unless collapse_key.nil?
      #str << "timeToLive=#{time_to_live.to_i}," unless time_to_live.nil?
      #str << "delayWhileIdle=#{delay_while_idle? ? '1': '0'}," unless delay_while_idle.nil?
      #
      #if (data.is_a?(Hash) && !data.empty?)
      #  str << "data: {"
      #  data.each {|key, value| str << key << "=" << value << ","}
      #  str.chomp!(',')
      #  str << "}"
      #end
      #
      #str.chomp!(',')
      #str << ")"
      #
      #str
    end
  end
end