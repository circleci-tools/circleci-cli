# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::RetryCommand, type: :command do
  let(:build_response) { CircleCI::CLI::Response::Build }

  shared_examples_for 'a command retries build' do
    it 'should retry build' do
      allow(CircleCI::CLI::Command::RetryCommand).to receive(:puts) { nil }
      expect(CircleCI::CLI::Command::RetryCommand).to receive(:puts).with(expected_output.strip)
      CircleCI::CLI::Command::RetryCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil) }
    let(:expected_output) { 'build user/project_name_from_io 1234 is triggered' }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command retries build'
  end

  context 'with project input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil) }
    let(:expected_output) { 'build unhappychoice/Circler 1234 is triggered' }

    it_behaves_like 'a command retries build'

    it 'retries the prompted build number' do
      expect(described_class).to receive(:ask).with('Input build number').and_return(98)
      expect(build_response).to receive(:retry).with('unhappychoice', 'Circler', 98).and_call_original

      described_class.run(options)
    end
  end

  context 'with build input' do
    let(:options) { OpenStruct.new(project: nil, build: 1234) }
    let(:expected_output) { 'build user/project_name_from_io 1234 is triggered' }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command retries build'

    it 'retries the explicit build number without prompting for one' do
      expect(described_class).not_to receive(:ask).with('Input build number')
      expect(build_response).to receive(:retry).with('user', 'project_name_from_io', 1234).and_call_original

      described_class.run(options)
    end
  end

  context 'with last option' do
    let(:options) { OpenStruct.new(project: 'unhappychoice/Circler', last: true) }
    let(:expected_output) { 'build unhappychoice/Circler 1234 is triggered' }

    it_behaves_like 'a command retries build'

    it 'selects the highest failed build number even when a build number is given' do
      options.build = 42
      expect(described_class).not_to receive(:ask).with('Input build number')
      failed_builds = [1232, 1234, 1233].map { |number| build_response.new('build_num' => number) }
      allow(build_response).to receive(:failed).with('unhappychoice', 'Circler').and_return(failed_builds)
      expect(build_response).to receive(:retry).with('unhappychoice', 'Circler', 1234).and_call_original

      described_class.run(options)
    end

    it 'reports no failed build and skips the follow-up request when the list is empty' do
      allow(build_response).to receive(:failed).with('unhappychoice', 'Circler').and_return([])
      expect(build_response).not_to receive(:retry)
      expect(described_class).to receive(:say).with('No failed build found.')

      described_class.run(options)
    end
  end

  context 'when retry fails' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: 1234) }
    let(:build_hash) { {} }

    it 'shows failure message' do
      allow(CircleCI::CLI::Command::RetryCommand).to receive(:puts) { nil }
      expect(CircleCI::CLI::Command::RetryCommand).to receive(:puts).with('failed to trigger unhappychoice/Circler 1234')
      CircleCI::CLI::Command::RetryCommand.run(options)
    end
  end
end
