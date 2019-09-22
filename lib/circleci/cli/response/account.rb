# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Account
        def initialize(hash)
          @hash = hash
        end

        def pusher_id
          @hash['pusher_id']
        end

        class << self
          def me
            Account.new(CircleCi::User.new.me.body)
          end
        end
      end
    end
  end
end
