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
    %w[running queued].each do |status|
      it "returns true for #{status}" do
        expect(described_class.new(base_attributes.merge('status' => status))).to be_running
      end
    end

    [nil, *%w[success canceled failed no_tests not_run]].each do |status|
      it "returns false for #{status.inspect}" do
        expect(described_class.new(base_attributes.merge('status' => status)).running?).to be(false)
      end
    end
  end

  describe '#finished?' do
    it 'recognizes a finished lifecycle with an unfamiliar status' do
      build = described_class.new(base_attributes.merge('lifecycle' => 'finished', 'status' => 'retried'))
      expect(build).to be_finished
    end

    it 'uses the lifecycle when it disagrees with the status' do
      build = described_class.new(base_attributes.merge('lifecycle' => 'running', 'status' => 'canceled'))
      expect(build).not_to be_finished
    end

    it 'recognizes a legacy terminal status when lifecycle is missing' do
      build = described_class.new(base_attributes.merge('status' => 'success'))
      expect(build).to be_finished
    end
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
