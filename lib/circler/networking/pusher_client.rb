require 'pusher-client'

class CirclerPusherClient
  def connect
    PusherClient.logger.level = Logger::ERROR
    @socket = PusherClient::Socket.new(app_key, pusher_options)
    @socket.connect(true)
  end

  def bind(channel, event)
    @socket.subscribe(channel)
    @socket[channel].bind(event) do |data|
      yield data
    end
  end

  def unsubscribe(channel)
    @socket.unsubscribe(channel)
  end

  private

  def app_key
    '1cf6e0e755e419d2ac9a'
  end

  def pusher_options
    {
      secure: true,
      auth_method: Proc.new { |a, b| auth(a, b) },
      logger: Logger.new('/dev/null')
    }
  end

  def auth(socket_id, channel)
    data = { socket_id: socket_id, channel_name: channel.name }
    token = ENV['CIRCLE_CI_TOKEN'] || ask('Circle CI token ? :')
    res = connection.post("/auth/pusher?circle-token=#{token}", data)
    JSON.parse(res.body)['auth']
  end

  def connection
    Faraday.new(url: 'https://circleci.com') do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end
  end
end
