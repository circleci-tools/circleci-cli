# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BaseCommand do
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
