# frozen_string_literal: true

module CircleCI
  module CLI
    module Response
      class Account
        def initialize(hash)
          @hash = hash
        end

        def user_name
          @hash['name']
        end

        def self.me
          Account.new(CircleCi::User.me.body)
        end
      end
    end
  end
end
