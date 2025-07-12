# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Step
        attr_reader :type, :name

        def initialize(type, hash)
          @type = type
          @name = hash['name']
          @hash = hash
        end

        def actions
          @hash['actions'].map { |a| Action.new(a) }
        end

        def status
          return 'running' if actions.any? { |action| action.end_time.nil? }
          return 'failed' if actions.any?(&:failed?)

          'success'
        end
      end
    end
  end
end
