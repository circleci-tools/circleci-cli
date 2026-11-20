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
            Account.new(Response.body!(CircleCi::User.new.me))
          end
        end
      end
    end
  end
end
