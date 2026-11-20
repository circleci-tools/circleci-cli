# frozen_string_literal: true

require 'pusher-client'
require 'circleci/cli/networking/verified_pusher_websocket'

module CircleCI
  module CLI
    module Networking
      class VerifiedPusherSocket < PusherClient::Socket
        protected

        def connect_internal
          open_connection
          logger.debug('Websocket connected')
          loop { @connection.receive.each { |message| dispatch_message(message) } }
        end

        private

        def open_connection
          websocket = VerifiedPusherWebSocket.new(@url, cert_file: @cert_file, logger: logger)
          websocket.connect
          @connection = websocket
        ensure
          websocket.close if websocket&.socket && !@connection.equal?(websocket)
        end

        def dispatch_message(message)
          params = parser(message)
          return if params['socket_id'] && params['socket_id'] == socket_id

          send_local_event(params['event'], params['data'], params['channel'])
        end
      end
    end
  end
end
