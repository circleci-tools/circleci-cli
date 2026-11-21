# frozen_string_literal: true

require 'circleci/cli/networking/verified_pusher_socket'

module CircleCI
  module CLI
    module Networking
      class CircleCIPusherClient
        def initialize(token:)
          @token = token
        end

        def connect
          return @connection_thread if @connection_thread&.alive?

          PusherClient.logger.level = Logger::ERROR
          connection = socket
          # The socket's async mode cannot disconnect before the handshake finishes.
          Thread.handle_interrupt(Interrupt => :never) do
            @connection_thread = Thread.new { connect_socket(connection) }
          end
        end

        def disconnect
          Thread.handle_interrupt(Interrupt => :never) do
            @connection_thread&.kill&.join
            @connection_thread = nil
            @socket&.disconnect
          end
        end

        def bind(channel, *events, &)
          socket.subscribe(channel)
          subscription = socket[channel]
          events.each { |event| subscription.bind(event, &) }
          subscription
        end

        def bind_event_json(channel, event, &)
          bind(channel, event) { |data| JSON.parse(data).each(&) }
        end

        def unsubscribe(channel)
          socket.unsubscribe(channel)
        rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
          # Pusher removes the local subscription before sending the unsubscribe event.
          nil
        end

        private

        def connect_socket(connection)
          connection.connect
        rescue StandardError => e
          connection.global_channel.dispatch_with_all('pusher:error', e)
        end

        def socket
          @socket ||= VerifiedPusherSocket.new(
            '1cf6e0e755e419d2ac9a',
            secure: true,
            auth_method: proc { |a, b| auth(a, b) },
            logger: Logger.new(File::NULL)
          )
        end

        def auth(socket_id, channel)
          res = HTTPClient.post_form('https://circleci.com/auth/pusher',
                                     { socket_id: socket_id, channel_name: channel.name },
                                     { 'Circle-Token' => @token })
          res['auth']
        end
      end
    end
  end
end
