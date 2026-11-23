# frozen_string_literal: true

require 'net/http'

module CircleCI
  module CLI
    module Command
      module WatchRequestErrors
        TRANSIENT = [
          Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, EOFError,
          Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::EPIPE
        ].freeze
      end
    end
  end
end
