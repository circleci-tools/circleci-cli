# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Networking::CircleCIPusherClient, type: :networking do
  describe '#connect' do
    subject { described_class.new.connect }

    let(:mock_socket) { double('socket') }

    it 'connects to socket' do
      allow(PusherClient).to receive_message_chain(:logger, :debug)
      allow(Net::HTTP).to receive(:post_form) { double(body: '{"auth":""}') }
      allow_any_instance_of(described_class).to receive(:socket) { mock_socket }

      expect(PusherClient).to receive_message_chain(:logger, :level=).with(Logger::ERROR)
      expect(mock_socket).to receive(:connect).with(true)

      subject
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
