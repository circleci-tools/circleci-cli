# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildCommand, type: :command do
  let(:build_response) { CircleCI::CLI::Response::Build }

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
      expect { described_class.run(options) }.to output(a_string_including(expected_output)).to_stdout
    end
  end

  context 'with a failed action' do
    let(:log) { 'Build log contains <%= "example" %>' }
    let(:action_name) { 'Test <%= "metadata" %>' }
    let(:output_url) { 'https://example.test/output' }

    before do
      build_hash['steps'].last['actions'].first.merge!(
        'name' => action_name, 'status' => 'failed', 'output_url' => output_url
      )
      http_client = CircleCI::CLI::Networking::HTTPClient
      allow(http_client).to receive(:get).with(output_url).and_return([{ 'message' => log }])
    end

    [true, false].each do |pretty|
      it "prints the action name and log literally with pretty=#{pretty}" do
        options = OpenStruct.new(project: 'user/repo', build: 1234, pretty:)
        expect { described_class.run(options) }.to output(a_string_including(action_name, log)).to_stdout
      end
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

    it 'fetches the prompted build number' do
      expect(described_class).to receive(:ask).with('Input build number').and_return(98)
      expect(build_response).to receive(:get).with('unhappychoice', 'Circler', 98).and_call_original

      described_class.run(options)
    end
  end

  context 'with build input' do
    let(:options) { OpenStruct.new(project: nil, build: 5, pretty: true) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show build information'

    it 'fetches the explicit build number without prompting for one' do
      expect(described_class).not_to receive(:ask).with('Input build number')
      expect(build_response).to receive(:get).with('user', 'project_name_from_io', 5).and_call_original

      described_class.run(options)
    end
  end

  context 'with last option' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil, last: true, pretty: true) }

    it_behaves_like 'a command show build information'

    it 'selects the highest failed build number even when a build number is given' do
      options.build = 42
      expect(described_class).not_to receive(:ask).with('Input build number')
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
