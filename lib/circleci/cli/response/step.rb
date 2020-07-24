# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Step
        attr_reader :type, :status

        def initialize(type, hash)
          @type = type
          @status = hash['status']
          @hash = hash
        end

        def actions
          @hash['actions'].map { |a| Action.new(a) }
        end
      end
    end
  end
end
