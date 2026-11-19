# frozen_string_literal: true

require 'pusher-client'

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

        def bind(channel, event, &)
          socket.subscribe(channel)
          socket[channel].bind(event, &)
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
          @socket ||= Socket.new(
            '1cf6e0e755e419d2ac9a',
            secure: true,
            auth_method: proc { |a, b| auth(a, b) },
            logger: Logger.new(File::NULL)
          )
        end

        def auth(socket_id, channel)
          res = HTTPClient.post_form("https://circleci.com/auth/pusher?circle-token=#{@token}",
                                     { socket_id: socket_id, channel_name: channel.name })
          res['auth']
        end

        class Socket < PusherClient::Socket
          private

          def connect_internal
            open_connection
            logger.debug('Websocket connected')

            loop { @connection.receive.each { |message| dispatch_message(message) } }
          end

          def open_connection
            # The initializer opens the TCP socket before completing either handshake.
            websocket = PusherClient::PusherWebSocket.allocate
            websocket.__send__(:initialize, @url, ssl: @encrypted, cert_file: @cert_file, ssl_verify: @ssl_verify)
            @connection = websocket
          ensure
            websocket&.socket&.close unless @connection.equal?(websocket)
          end

          def dispatch_message(message)
            params = parser(message)
            return if params['socket_id'] && params['socket_id'] == socket_id

            send_local_event(params['event'], params['data'], params['channel'])
          end
        end
        private_constant :Socket
      end
    end
  end
end
