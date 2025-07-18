# frozen_string_literal: true

require 'pusher-client'

module CircleCI
  module CLI
    module Networking
      class CircleCIPusherClient
        def connect
          PusherClient.logger.level = Logger::ERROR
          socket.connect(true)
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
        end

        private

        def socket
          @socket ||= PusherClient::Socket.new(
            '1cf6e0e755e419d2ac9a',
            secure: true,
            auth_method: proc { |a, b| auth(a, b) },
            logger: Logger.new(File::NULL)
          )
        end

        def auth(socket_id, channel)
          token = ENV.fetch('CIRCLE_CI_TOKEN', nil) || ask('Circle CI token ? :')
          res = HTTPClient.post_form("https://circleci.com/auth/pusher?circle-token=#{token}",
                                     { socket_id: socket_id, channel_name: channel.name })
          res['auth']
        end
      end
    end
  end
end
