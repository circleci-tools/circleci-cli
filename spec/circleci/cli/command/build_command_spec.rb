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
    let(:action_status) { 'failed' }
    let(:output_url) { 'https://example.test/output' }
    let(:response) { Net::HTTPOK.new('1.1', '200', 'OK') }
    let(:response_body) { JSON.generate([{ 'message' => log }]) }

    before do
      build_hash['steps'].last['actions'].first.merge!(
        'name' => action_name, 'status' => action_status, 'output_url' => output_url,
        'end_time' => '2026-11-23T00:00:00Z'
      )
      session_class = CircleCI::CLI::Networking::HTTPClient::Session
      log_session = instance_double(session_class, close: nil)
      allow(session_class).to receive(:new).and_return(log_session)
      allow(log_session).to receive(:get_raw).with(output_url).and_yield(response)
      allow(response).to receive(:read_body).and_yield(response_body)
    end

    [true, false].each do |pretty|
      it "prints the action name and log literally with pretty=#{pretty}" do
        options = OpenStruct.new(project: 'user/repo', build: 1234, pretty:)
        expect { described_class.run(options) }.to output(a_string_including(action_name, log)).to_stdout
      end

      context "when the log download returns HTTP 403 with pretty=#{pretty}" do
        let(:response) { Net::HTTPForbidden.new('1.1', '403', 'Forbidden') }
        let(:response_body) { '{"message":"Access denied"}' }

        it 'reports the HTTP error on stderr and exits unsuccessfully' do
          layout = pretty ? '--pretty' : '--no-pretty'
          arguments = %w[build -p user/repo -n 1234] + [layout]

          expect do
            expect { CircleCI::CLI::Runner.start(arguments) }.to raise_error(SystemExit) { |error|
              expect(error.status).not_to be_zero
            }
          end.to output("Action log download failed (HTTP 403)\n").to_stderr
        end
      end
    end

    context 'when the action failed due to an infrastructure error' do
      let(:action_status) { 'infrastructure_fail' }

      it 'prints the action log' do
        options = OpenStruct.new(project: 'user/repo', build: 1234, pretty: true)
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

  context 'with a failed action log' do
    let(:options) { OpenStruct.new(project: 'unhappychoice/Circler', build: 5, pretty: pretty) }
    let(:output_url) { 'https://circleci.com/output/123' }
    let(:long_line) { "#{'a' * 120}tail" }

    before do
      build_hash['steps'].last['actions'].first.merge!('status' => 'failed', 'output_url' => output_url)
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:read_body).and_yield(JSON.generate([{ 'message' => "before\n\nafter\e[2K\n#{long_line}\n" }]))
      session_class = CircleCI::CLI::Networking::HTTPClient::Session
      log_session = instance_double(session_class, close: nil)
      allow(session_class).to receive(:new).and_return(log_session)
      allow(log_session).to receive(:get_raw).with(output_url).and_yield(response)
    end

    context 'with table output' do
      let(:pretty) { true }

      it 'preserves blank rows and wraps long lines' do
        expected_rows = satisfy do |output|
          rows = output.lines.map { |line| line.split('|')[1]&.strip }
          rows.drop_while { |row| row != 'before' }.take(5) == ['before', '', 'after\x1B[2K', 'a' * 120, 'tail']
        end
        expect { described_class.run(options) }.to output(expected_rows).to_stdout
      end
    end

    context 'with compact output' do
      let(:pretty) { false }

      it 'preserves blank lines and leaves long lines intact' do
        expect { described_class.run(options) }.to output(end_with("before\n\nafter\\x1B[2K\n#{long_line}\n")).to_stdout
      end
    end
  end
end
