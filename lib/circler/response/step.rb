module Circler
  class Step
    attr_reader :type

    def initialize(type, hash)
      @type = type
      @hash = hash
    end

    def actions
      @hash.flat_map { |s| s['actions'] }
    end

    def logs
      actions.map do |a|
        Faraday.new(a.output_url).get.body
      end
    end
  end
end
