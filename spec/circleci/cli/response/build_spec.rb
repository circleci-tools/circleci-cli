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

    context 'when the build is canceled' do
      let(:status) { 'canceled' }

      it 'colorizes the status and branch in yellow' do
        expect(information[1]).to eq(CircleCI::CLI::Printer.colorize_yellow('canceled'))
        expect(information[2]).to eq(CircleCI::CLI::Printer.colorize_yellow('main'))
      end
    end

    context 'when the build has no tests' do
      let(:status) { 'no_tests' }

      it 'colorizes the status and branch in light black' do
        expect(information[1]).to eq(CircleCI::CLI::Printer.colorize_light_black('no_tests'))
        expect(information[2]).to eq(CircleCI::CLI::Printer.colorize_light_black('main'))
      end
    end

    context 'when the build status is not colorized' do
      let(:status) { 'running' }

      it 'returns the raw status and branch' do
        expect(information[1]).to eq('running')
        expect(information[2]).to eq('main')
      end
    end
  end
end
