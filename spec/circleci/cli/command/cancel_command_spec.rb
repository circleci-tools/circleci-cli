# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::CancelCommand, type: :command do
  shared_examples_for 'a command cancels build' do
    let(:expected_output) { 'build user/project_name_from_api 1234 is canceled.' }

    it 'should cancel build' do
      allow(CircleCI::CLI::Command::CancelCommand).to receive(:say) { nil }
      expect(CircleCI::CLI::Command::CancelCommand).to receive(:say).with(expected_output.strip)
      CircleCI::CLI::Command::CancelCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command cancels build'
  end

  context 'with project input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil) }

    it_behaves_like 'a command cancels build'
  end

  context 'with branch input' do
    let(:options) { OpenStruct.new(project: nil, build: 1234) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command cancels build'
  end
end
