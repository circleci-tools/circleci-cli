# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildCommand, type: :command do
  shared_examples_for 'a command show build information' do
    let(:expected_output) do
      <<~EXPECTED
        +---------------+
        +---------------+
        |     \e[0;32;49mbuild\e[0m     |
        +-------+-------+
        | \e[0;32;49mBuild\e[0m | 00:01 |
        +-------+-------+
        |     \e[0;32;49mtest\e[0m      |
        +-------+-------+
        | \e[0;32;49mTest\e[0m  | 00:01 |
        +-------+-------+
      EXPECTED
    end

    it 'should show build information' do
      allow(CircleCI::CLI::Command::BuildCommand).to receive(:say) { nil }
      expect(CircleCI::CLI::Command::BuildCommand).to receive(:say).with(expected_output.strip)
      CircleCI::CLI::Command::BuildCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil, pretty: true) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show build information'
  end

  context 'with project input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil, pretty: true) }

    it_behaves_like 'a command show build information'
  end

  context 'with build input' do
    let(:options) { OpenStruct.new(project: nil, build: 5, pretty: true) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show build information'
  end

  context 'with last option' do
    let(:build_response) { CircleCI::CLI::Response::Build }
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil, last: true, pretty: true) }

    it_behaves_like 'a command show build information'

    it 'selects the highest failed build number' do
      failed_builds = [1232, 1234, 1233].map { |number| build_response.new('build_num' => number) }
      allow(build_response).to receive(:failed).with('unhappychoice', 'Circler').and_return(failed_builds)
      expect(build_response).to receive(:get).with('unhappychoice', 'Circler', 1234).and_call_original

      described_class.run(options)
    end

    it 'reports no failed build and skips the follow-up request when the list is empty' do
      allow(build_response).to receive(:failed).with('unhappychoice', 'Circler').and_return([])
      expect(build_response).not_to receive(:get)
      expect(described_class).to receive(:say).with('No failed build found.')

      described_class.run(options)
    end
  end
end
