class OpenapiResolver
  class Error < StandardError
    def self.wrap(e)
      e.is_a?(self) ? e : new("#{e.class.name} #{e.message}").tap { _1.set_backtrace(e.backtrace) }
    end

    def add_message(message)
      @messages ||= []
      @messages << message
      self
    end

    def message
      msg = super
      msg += "\n" + @messages.join("\n") if @messages
      msg
    end
  end
end
