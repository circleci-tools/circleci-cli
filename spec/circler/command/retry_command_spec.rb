# frozen_string_literal: true

require 'spec_helper'

describe Circler::RetryCommand, type: :command do
  shared_examples_for 'a command retries build' do
    it 'should retry build' do
      allow(Circler::RetryCommand).to receive(:say) {}
      expect(Circler::RetryCommand).to receive(:say).with(expected_output.strip)
      Circler::RetryCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil) }
    let(:expected_output) { 'build unhappychoice/default_project_name_from_io 1234 is triggered' }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command retries build'
  end

  context 'with project input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil) }
    let(:expected_output) { 'build unhappychoice/Circler 1234 is triggered' }

    it_behaves_like 'a command retries build'
  end

  context 'with branch input' do
    let(:options) { OpenStruct.new(project: nil, build: 1234) }
    let(:expected_output) { 'build unhappychoice/default_project_name_from_io 1234 is triggered' }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command retries build'
  end
end
