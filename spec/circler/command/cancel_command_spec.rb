# frozen_string_literal: true

require 'spec_helper'

describe Circler::CancelCommand, type: :command do # rubocop:disable Metrics/BlockLength
  shared_examples_for 'a command cancels build' do
    let(:expected_output) { 'build unhappychoice/default_reponame_from_api 1234 is canceled.' }

    it 'should show build information' do
      allow(Circler::CancelCommand).to receive(:say) {}
      expect(Circler::CancelCommand).to receive(:say).with(expected_output.strip)
      Circler::CancelCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil) }
    let(:expected_url) { 'https://circleci.com/gh/unhappychoice/default_project_name_from_io' }
    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command cancels build'
  end

  context 'with project input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil) }
    let(:expected_url) { "https://circleci.com/gh/#{project_name}" }
    it_behaves_like 'a command cancels build'
  end

  context 'with branch input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: nil, build: 1234) }
    let(:expected_url) { "https://circleci.com/gh/#{project_name}" }
    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command cancels build'
  end
end
