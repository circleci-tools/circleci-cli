# frozen_string_literal: true

require 'net/http'
require 'circleci/cli/networking/http_client'

module CircleCI
  module CLI
    module Command
      module WatchRequestErrors
        TRANSIENT = Networking::HTTPClient::TRANSIENT_ERRORS
      end
    end
  end
end
