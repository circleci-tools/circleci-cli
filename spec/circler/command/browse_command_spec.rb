# frozen_string_literal: true

require 'spec_helper'

describe Circler::BrowseCommand, type: :command do # rubocop:disable Metrics/BlockLength
  shared_examples_for 'a command opens browser' do
    it 'should open browser' do
      allow(Circler::BrowseCommand).to receive(:say)
      expect(Launchy).to receive(:open).with(expected_url)
      Circler::BrowseCommand.run(options)
    end
  end

  shared_examples_for 'a command asks project name' do
    let(:expected_output) do
      <<~EXPECTED
        +---------------+---------------------------+
        |                 \e[0;32;49mProjects\e[0m                  |
        +---------------+---------------------------+
        | User name     | Repository name           |
        +---------------+---------------------------+
        | unhappychoice | default_reponame_from_api |
        +---------------+---------------------------+
      EXPECTED
    end

    it 'should show project list' do
      allow(Launchy).to receive(:open)
      expect(Circler::BrowseCommand).to receive(:say).with(expected_output.strip)
      Circler::BrowseCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil) }
    let(:expected_url) { 'https://circleci.com/gh/unhappychoice/default_project_name_from_io' }
    it_behaves_like 'a command opens browser'
    it_behaves_like 'a command asks project name'
  end

  context 'with project input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil) }
    let(:expected_url) { "https://circleci.com/gh/#{project_name}" }
    it_behaves_like 'a command opens browser'
  end

  context 'with build input' do
    let(:options) { OpenStruct.new(project: nil, build: 5) }
    let(:expected_url) { 'https://circleci.com/gh/unhappychoice/default_project_name_from_io/5' }
    it_behaves_like 'a command opens browser'
    it_behaves_like 'a command asks project name'
  end
end
