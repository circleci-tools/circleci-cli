# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Step
        attr_reader :name, :identity

        def initialize(hash, identity = nil)
          @name = hash['name']
          @identity = identity
          @hash = hash
        end

        def actions
          @hash['actions'].map { |a| Action.new(a) }
        end

        def status
          actions = self.actions
          return 'running' if actions.any?(&:running?)
          return 'failed' if actions.any?(&:failed?)
          return 'canceled' if actions.any?(&:canceled?)
          return 'not_run' if all_skipped?(actions)

          'success'
        end

        private

        def all_skipped?(actions)
          !actions.empty? && actions.all?(&:skipped?)
        end
      end
    end
  end
end
