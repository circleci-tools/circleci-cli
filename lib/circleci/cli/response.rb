# frozen_string_literal: true

require 'circleci/cli/response/account'
require 'circleci/cli/response/project'
require 'circleci/cli/response/build'
require 'circleci/cli/response/step'
require 'circleci/cli/response/action'

module CircleCI
  module CLI
    module Response
      def self.body!(response)
        body = response.body
        return body if response.success?

        message = "CircleCI API error (HTTP #{response.code})"
        detail = body['message'] if body.is_a?(Hash)
        message += ": #{detail}" if detail.is_a?(String) && !detail.strip.empty?
        raise Thor::Error, message
      end
    end
  end
end
