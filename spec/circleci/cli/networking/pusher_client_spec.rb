# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Networking::CircleCIPusherClient, type: :networking do
  describe '#connect' do
    subject(:connect) { client.connect }

    let(:client) { described_class.new(token: 'token') }
    let(:mock_socket) { double('socket') }
    let(:mock_logger) { double('logger') }
    let(:socket_options) { {} }
    let(:http) { instance_double(Net::HTTP) }

    before do
      allow(PusherClient).to receive(:logger).and_return(mock_logger)
      allow(mock_logger).to receive(:level=)
      allow(mock_socket).to receive(:connect)
      allow(CircleCI::CLI::Networking::VerifiedPusherSocket).to receive(:new) do |key, options|
        socket_options[:key] = key
        socket_options.merge!(options)
        mock_socket
      end
    end

    it 'builds a secure socket and connects to it' do
      connect.join

      expect(mock_logger).to have_received(:level=).with(Logger::ERROR)
      expect(socket_options[:key]).to eq('1cf6e0e755e419d2ac9a')
      expect(socket_options[:secure]).to be(true)
      expect(socket_options[:auth_method]).to be_a(Proc)
      expect(socket_options[:logger]).to be_a(Logger)
      expect(mock_socket).to have_received(:connect).with(no_args)
    end

    it 'dispatches connection failures to the global error channel' do
      error = IOError.new('connection failed')
      channel = double('global channel')
      allow(mock_socket).to receive(:global_channel).and_return(channel)
      allow(mock_socket).to receive(:connect).and_raise(error)
      expect(channel).to receive(:dispatch_with_all).with('pusher:error', error)

      connect.join
    end

    it 'authenticates repeated private-channel requests with the token in the header' do
      response = instance_double(Net::HTTPOK, body: '{"auth":"signed"}')
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).and_return(response)

      connect.join

      channel = double('channel', name: 'private-builds')
      auth = socket_options.fetch(:auth_method)

      %w[first-socket second-socket].each do |socket_id|
        expect(auth.call(socket_id, channel)).to eq('signed')
        expect(http).to have_received(:request).with(an_instance_of(Net::HTTP::Post).and(satisfy do |request|
          request.uri == URI('https://circleci.com/auth/pusher') &&
            request['Circle-Token'] == 'token' &&
            request.content_type == 'application/x-www-form-urlencoded' &&
            URI.decode_www_form(request.body).to_h == { 'socket_id' => socket_id, 'channel_name' => 'private-builds' }
        end)).once
      end
    end
  end

  describe '#disconnect' do
    let(:client) { described_class.new(token: 'token') }
    let(:socket_pair) { Socket.pair(:UNIX, :STREAM) }
    let(:tcp_socket) { socket_pair.first }
    let(:peer) { socket_pair.last }

    before do
      allow(TCPSocket).to receive(:new).and_return(tcp_socket)
      allow(OpenSSL::SSL::SSLSocket).to receive(:new).with(tcp_socket, anything).and_return(tcp_socket)
      allow(tcp_socket).to receive(:sync_close=).with(true)
      allow(tcp_socket).to receive(:hostname=).with('ws.pusherapp.com')
      allow(tcp_socket).to receive(:connect).with(no_args).and_return(tcp_socket)
    end

    after do
      client.disconnect
      socket_pair.each { |socket| socket.close unless socket.closed? }
    end

    it 'stops the connection thread and closes the TCP socket during the TLS handshake' do
      started = Queue.new
      pending = Queue.new
      ssl = instance_double(OpenSSL::SSL::SSLSocket)
      allow(ssl).to receive(:sync_close=).with(true)
      allow(ssl).to receive(:hostname=).with('ws.pusherapp.com')
      allow(ssl).to receive(:close) { tcp_socket.close }
      allow(OpenSSL::SSL::SSLSocket).to receive(:new).with(tcp_socket, anything).and_return(ssl)
      allow(ssl).to receive(:connect) do
        started << true
        pending.pop
      end

      worker = client.connect
      expect(started.pop(timeout: 5)).to be(true)
      expect(client.connect).to equal(worker)
      client.disconnect

      expect(worker).not_to be_alive
      expect(tcp_socket).to be_closed
    end

    it 'closes the socket when interrupted while waiting for the WebSocket upgrade' do
      worker = client.connect
      expect(Timeout.timeout(5) { peer.gets("\r\n\r\n") }).to start_with('GET ')

      client.disconnect

      expect(worker).not_to be_alive
      expect(tcp_socket).to be_closed
    end

    it 'dispatches events after the WebSocket handshake and closes the connection on disconnect' do
      events = Queue.new

      client.bind('builds', 'updated') { |data| events << data }
      client.connect
      handshake = WebSocket::Handshake::Server.new
      handshake << Timeout.timeout(5) { peer.gets("\r\n\r\n") }
      peer.write(handshake.to_s)
      payload = { event: 'updated', channel: 'builds', data: 'passed' }.to_json
      frame = WebSocket::Frame::Outgoing::Server.new(version: handshake.version, data: payload, type: :text)
      peer.write(frame.to_s)

      expect(events.pop(timeout: 5)).to eq('passed')
      client.disconnect
      expect(tcp_socket).to be_closed
    end
  end

  describe '#bind' do
    subject { described_class.new(token: 'token').bind(channel, event) }

    let(:mock_socket) { double('socket') }
    let(:mock_channel) { double('channel') }
    let(:channel) { 'channel' }
    let(:event) { 'event' }

    it 'binds event' do
      allow_any_instance_of(described_class).to receive(:socket) { mock_socket }

      expect(mock_socket).to receive(:subscribe).with(channel)
      expect(mock_socket).to receive(:[]).with(channel) { mock_channel }
      expect(mock_channel).to receive(:bind).with(event)

      subject
    end
  end

  describe '#bind_event_json' do
    subject { described_class.new(token: 'token').bind_event_json(channel, event) }
    let(:mock_socket) { double('socket') }
    let(:mock_channel) { double('channel') }
    let(:channel) { 'channel' }
    let(:event) { 'event' }

    it 'binds event' do
      allow_any_instance_of(described_class).to receive(:socket) { mock_socket }

      expect(mock_socket).to receive(:subscribe).with(channel)
      expect(mock_socket).to receive(:[]).with(channel) { mock_channel }
      expect(mock_channel).to receive(:bind).with(event)

      subject
    end
  end

  describe '#unsubscribe' do
    subject { described_class.new(token: 'token').unsubscribe(channel) }

    let(:mock_socket) { double('socket') }
    let(:channel) { 'channel' }

    it 'unsubscribes channel' do
      allow_any_instance_of(described_class).to receive(:socket) { mock_socket }
      expect(mock_socket).to receive(:unsubscribe).with(channel)

      subject
    end
  end
end
