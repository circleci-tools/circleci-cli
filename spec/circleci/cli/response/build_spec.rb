# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Response::Build do
  let(:base_attributes) do
    {
      'username' => 'octocat',
      'reponame' => 'hello-world',
      'build_num' => 42,
      'branch' => 'main',
      'author_name' => 'octocat',
      'build_time_millis' => 61_000,
      'start_time' => '2024-01-01T00:00:00Z'
    }
  end

  describe '#running?' do
    subject(:running?) { described_class.new(base_attributes.merge('status' => 'running')).running? }

    it { is_expected.to be(true) }
  end

  describe '#channel_name' do
    subject(:channel_name) { described_class.new(base_attributes).channel_name }

    it { is_expected.to eq('private-octocat@hello-world@42@vcs-github@0') }
  end

  describe '#information' do
    subject(:information) { described_class.new(base_attributes.merge('status' => status)).information }

    let(:status) { 'canceled' }

    it 'returns raw build information' do
      expect(information).to eq([42, 'canceled', 'main', 'octocat', '', '01:01', '2024-01-01T00:00:00Z'])
    end
  end
end
