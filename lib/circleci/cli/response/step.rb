# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Step
        attr_reader :name

        def initialize(hash)
          @name = hash['name']
          @hash = hash
        end

        def actions
          @hash['actions'].map { |a| Action.new(a) }
        end

        def action_identity
          actions.first&.identity
        end

        def status
          return 'running' if actions.any?(&:running?)
          return 'failed' if actions.any?(&:failed?)

          'success'
        end
      end
    end
  end
end
