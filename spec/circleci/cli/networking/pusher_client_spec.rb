# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Networking::CircleCIPusherClient, type: :networking do
  describe '#connect' do
    subject(:connect) { client.connect }

    let(:client) { described_class.new(token: 'token') }
    let(:mock_socket) { double('socket') }
    let(:mock_logger) { double('logger') }
    let(:socket_options) { {} }

    before do
      allow(PusherClient).to receive(:logger).and_return(mock_logger)
      allow(mock_logger).to receive(:level=)
      allow(mock_socket).to receive(:connect)
      allow(described_class.const_get(:Socket)).to receive(:new) do |key, options|
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

    it 'reuses the supplied token for repeated auth callbacks' do
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:post_form).and_return('auth' => 'signed')

      connect.join

      channel = double('channel', name: 'private-builds')
      auth = socket_options.fetch(:auth_method)

      %w[first-socket second-socket].each do |socket_id|
        expect(auth.call(socket_id, channel)).to eq('signed')
        expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:post_form).with(
          'https://circleci.com/auth/pusher?circle-token=token',
          socket_id: socket_id,
          channel_name: 'private-builds'
        ).once
      end
    end
  end

  describe '#disconnect' do
    it 'stops the connection thread and closes the TCP socket during the TLS handshake' do
      client = described_class.new(token: 'token')
      started = Queue.new
      pending = Queue.new
      tcp_socket, peer = Socket.pair(:UNIX, :STREAM)
      tls_socket = instance_double(OpenSSL::SSL::SSLSocket)
      allow(tls_socket).to receive(:sync_close=).with(true)
      allow(TCPSocket).to receive(:new).and_return(tcp_socket)
      allow(OpenSSL::SSL::SSLSocket).to receive(:new).with(tcp_socket, anything).and_return(tls_socket)
      allow(tls_socket).to receive(:connect) do
        started << true
        pending.pop
      end

      worker = client.connect
      expect(started.pop(timeout: 5)).to be(true)
      expect(client.connect).to equal(worker)
      client.disconnect

      expect(worker).not_to be_alive
      expect(tcp_socket).to be_closed
    ensure
      client.disconnect
      tcp_socket&.close unless tcp_socket&.closed?
      peer&.close
    end

    it 'dispatches events after the WebSocket handshake and closes the connection on disconnect' do
      client = described_class.new(token: 'token')
      events = Queue.new
      tcp_socket, peer = Socket.pair(:UNIX, :STREAM)
      allow(TCPSocket).to receive(:new).and_return(tcp_socket)
      allow(OpenSSL::SSL::SSLSocket).to receive(:new).with(tcp_socket, anything).and_return(tcp_socket)
      allow(tcp_socket).to receive(:sync_close=).with(true)
      allow(tcp_socket).to receive(:connect).with(no_args)

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
    ensure
      client.disconnect
      tcp_socket&.close unless tcp_socket&.closed?
      peer&.close
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
