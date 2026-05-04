# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Networking::CircleCIPusherClient, type: :networking do
  describe '#connect' do
    subject(:connect) { client.connect }

    let(:client) { described_class.new }
    let(:mock_socket) { double('socket') }
    let(:mock_logger) { double('logger') }
    let(:socket_options) { {} }

    before do
      allow(PusherClient).to receive(:logger).and_return(mock_logger)
      allow(mock_logger).to receive(:level=)
      allow(mock_socket).to receive(:connect)
      allow(PusherClient::Socket).to receive(:new) do |key, options|
        socket_options[:key] = key
        socket_options.merge!(options)
        mock_socket
      end
    end

    it 'builds a secure socket and connects to it' do
      connect

      expect(mock_logger).to have_received(:level=).with(Logger::ERROR)
      expect(socket_options[:key]).to eq('1cf6e0e755e419d2ac9a')
      expect(socket_options[:secure]).to be(true)
      expect(socket_options[:auth_method]).to be_a(Proc)
      expect(socket_options[:logger]).to be_a(Logger)
      expect(mock_socket).to have_received(:connect).with(true)
    end

    it 'uses the environment token in the auth callback' do
      allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('token')
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:post_form).and_return('auth' => 'signed')

      connect

      channel = double('channel', name: 'private-builds')
      result = socket_options.fetch(:auth_method).call('socket-id', channel)

      expect(result).to eq('signed')
      expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:post_form).with(
        'https://circleci.com/auth/pusher?circle-token=token',
        socket_id: 'socket-id',
        channel_name: 'private-builds'
      )
    end

    it 'prompts for a token when the environment token is missing' do
      allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return(nil)
      allow(client).to receive(:ask).with('Circle CI token ? :').and_return('prompted-token')
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:post_form).and_return('auth' => 'signed')

      connect

      channel = double('channel', name: 'private-builds')
      socket_options.fetch(:auth_method).call('socket-id', channel)

      expect(client).to have_received(:ask).with('Circle CI token ? :')
      expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:post_form).with(
        'https://circleci.com/auth/pusher?circle-token=prompted-token',
        socket_id: 'socket-id',
        channel_name: 'private-builds'
      )
    end
  end

  describe '#bind' do
    subject { described_class.new.bind(channel, event) }

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
    subject { described_class.new.bind_event_json(channel, event) }
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
    subject { described_class.new.unsubscribe(channel) }

    let(:mock_socket) { double('socket') }
    let(:channel) { 'channel' }

    it 'unsubscribes channel' do
      allow_any_instance_of(described_class).to receive(:socket) { mock_socket }
      expect(mock_socket).to receive(:unsubscribe).with(channel)

      subject
    end
  end
end
