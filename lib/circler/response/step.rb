module Circler
  class Step
    attr_reader :type
    attr_reader :status

    def initialize(type, hash)
      @type = type
      @status = hash['status']
      @hash = hash
    end

    def actions
      @hash['actions'].map{ |a| Action.new(a) }
    end
  end
end
