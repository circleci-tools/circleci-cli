# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BaseCommand do
  describe '.setup_token' do
    let(:config) { double('CircleCI configuration') }

    before { allow(CircleCi).to receive(:configure).and_yield(config) }

    it 'passes the token from the hidden prompt to the API configuration' do
      allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return(nil)
      question = HighLine::Question.new('Circle CI token ? :', String)
      allow(described_class).to receive(:ask).and_yield(question).and_return('prompted-token')
      expect(config).to receive(:token=).with('prompted-token')

      described_class.setup_token

      expect(question.echo).to be(false)
    end

    it 'uses the environment token without prompting' do
      allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('environment-token')
      expect(described_class).not_to receive(:ask)
      expect(config).to receive(:token=).with('environment-token')

      described_class.setup_token
    end
  end

  describe '#branch_name' do
    subject { described_class.branch_name(options) }
    let(:options) { OpenStruct.new }

    context 'with all option' do
      let(:options) { OpenStruct.new(all: true) }
      let(:rugged_response_branch_name) { 'branch' }
      let(:rugged_response_is_branch) { true }

      it { is_expected.to eq(nil) }
    end

    context 'with branch option' do
      let(:options) { OpenStruct.new(branch: 'optionBranch') }
      let(:rugged_response_branch_name) { 'branch' }
      let(:rugged_response_is_branch) { true }

      it { is_expected.to eq('optionBranch') }
    end

    context 'with nothing' do
      let(:options) { OpenStruct.new }
      let(:rugged_response_branch_name) { nil }
      let(:rugged_response_is_branch) { false }

      it { is_expected.to eq(nil) }
    end
  end
end
