# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Response::Account do
  describe '#pusher_id' do
    subject(:pusher_id) { described_class.new('pusher_id' => 'pusher-123').pusher_id }

    it { is_expected.to eq('pusher-123') }
  end

  describe '.me' do
    subject(:account) { described_class.me }

    let(:body) { { 'pusher_id' => 'pusher-123' } }
    let(:response) { double(body: body) }
    let(:user) { double(me: response) }

    before do
      allow(CircleCi::User).to receive(:new).and_return(user)
    end

    it 'returns the current account' do
      expect(account.pusher_id).to eq('pusher-123')
      expect(CircleCi::User).to have_received(:new)
    end
  end
end
