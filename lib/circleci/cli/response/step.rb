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
          acts = actions
          precedence_status(acts) || (all_skipped?(acts) ? 'not_run' : 'success')
        end

        PRECEDENCE = [[:running?, 'running'], [:failed?, 'failed'], [:canceled?, 'canceled']].freeze

        private

        def precedence_status(acts)
          _, value = PRECEDENCE.find { |predicate, _| acts.any?(&predicate) }
          value
        end

        def all_skipped?(actions)
          !actions.empty? && actions.all?(&:skipped?)
        end
      end
    end
  end
end
