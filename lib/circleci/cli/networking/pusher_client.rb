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
          res = connection.post(
            "/auth/pusher?circle-token=#{token}",
            { socket_id:, channel_name: channel.name }
          )
          JSON.parse(res.body)['auth']
        end

        def connection
          Faraday.new(url: 'https://circleci.com') do |f|
            f.request :url_encoded
            f.adapter Faraday.default_adapter
          end
        end
      end
    end
  end
end
