# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BrowseCommand, type: :command do
  shared_examples_for 'a command opens browser' do
    it 'should open browser' do
      allow(CircleCI::CLI::Command::BrowseCommand).to receive(:say)
      expect(Launchy).to receive(:open).with(expected_url)
      CircleCI::CLI::Command::BrowseCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil) }
    let(:expected_url) { 'https://circleci.com/gh/user/project_name_from_io' }

    it_behaves_like 'a command opens browser'
    it_behaves_like 'a command asks project name'
  end

  context 'with project input' do
    let(:io_response_project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: io_response_project_name, build: nil) }
    let(:expected_url) { "https://circleci.com/gh/#{io_response_project_name}" }

    it_behaves_like 'a command opens browser'
  end

  context 'with build input' do
    let(:options) { OpenStruct.new(project: nil, build: 5) }
    let(:expected_url) { 'https://circleci.com/gh/user/project_name_from_io/5' }

    it_behaves_like 'a command opens browser'
    it_behaves_like 'a command asks project name'
  end
end
