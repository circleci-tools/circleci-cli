# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BrowseCommand, type: :command do
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return(nil)
  end

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

    it 'configures authentication before listing projects' do
      expect(described_class).to receive(:ask).with('Circle CI token ? :').and_return(io_response_circle_ci_token)
      expect(CircleCI::CLI::Response::Project).to receive(:all).and_wrap_original do |list_projects|
        expect(CircleCi.config.token).to eq(io_response_circle_ci_token)
        list_projects.call
      end
      allow(described_class).to receive(:say)
      expect(Launchy).to receive(:open).with(expected_url)

      described_class.run(options)
    end
  end

  shared_examples_for 'browsing a known project' do
    it 'opens the project without prompting or listing projects' do
      expect(described_class).not_to receive(:ask)
      expect(CircleCI::CLI::Response::Project).not_to receive(:all)
      expect(Launchy).to receive(:open).with(expected_url)

      described_class.run(options)
    end
  end

  context 'with project input' do
    let(:options) { OpenStruct.new(project: 'unhappychoice/Circler', build: nil) }
    let(:expected_url) { 'https://circleci.com/gh/unhappychoice/Circler' }

    it_behaves_like 'browsing a known project'
  end

  context 'with a project inferred from Git' do
    let(:options) { OpenStruct.new(project: CircleCI::CLI::Runner.project, build: 5) }
    let(:expected_url) { 'https://circleci.com/gh/user/local-repository-from-rugged/5' }

    it_behaves_like 'browsing a known project'
  end

  context 'with build input' do
    let(:options) { OpenStruct.new(project: nil, build: 5) }
    let(:expected_url) { 'https://circleci.com/gh/user/project_name_from_io/5' }

    it_behaves_like 'a command opens browser'
    it_behaves_like 'a command asks project name'
  end
end
