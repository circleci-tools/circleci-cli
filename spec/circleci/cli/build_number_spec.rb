# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Runner, type: :command do
  let(:build_response) { CircleCI::CLI::Response::Build }
  let(:project_args) { %w[--project octocat/hello-world] }
  let(:error_output) { "Build number must be a positive integer.\n" }

  shared_examples 'build number validation' do |command, operation|
    %w[42.5 42.0 0 -1 invalid].each do |invalid_number|
      it "rejects #{invalid_number.inspect} from the build option" do
        expect(operation == :open ? Launchy : build_response).not_to receive(operation)
        expect do
          expect do
            described_class.start([command, *project_args, '-n', invalid_number])
          end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output(error_output).to_stderr
      end
    end
  end

  it_behaves_like 'build number validation', 'browse', :open

  it 'opens the URL for a valid build option' do
    expect(Launchy).to receive(:open).with('https://circleci.com/gh/octocat/hello-world/42')
    described_class.start(['browse', *project_args, '--build', '42'])
  end

  { 'build' => :get, 'retry' => :retry, 'cancel' => :cancel }.each do |command, operation|
    describe command do
      let(:build) { CircleCI::CLI::Response::Build.new(build_hash) }

      it_behaves_like 'build number validation', command, operation

      it 'sends a valid build option as an integer' do
        expect(build_response).to receive(operation).with('octocat', 'hello-world', 42).and_return(build)
        described_class.start([command, *project_args, '--build', '42'])
      end

      context 'when prompted' do
        let(:io_response_build_number) { '42' }

        it 'sends a valid answer as an integer' do
          expect(build_response).to receive(operation).with('octocat', 'hello-world', 42).and_return(build)
          described_class.start([command, *project_args])
        end

        ['42.5', '0', '-1', 'invalid', ''].each do |invalid_number|
          context "with #{invalid_number.inspect}" do
            let(:io_response_build_number) { invalid_number }

            it 'reports the error before sending the request' do
              expect(build_response).not_to receive(operation)
              expect do
                expect do
                  described_class.start([command, *project_args])
                end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
              end.to output(error_output).to_stderr
            end
          end
        end
      end
    end
  end

  %w[build retry].each do |command|
    it "uses the last failed build when a valid build option is also supplied for #{command}" do
      build = build_response.new(build_hash.merge('build_num' => 99))
      operation = command == 'build' ? :get : :retry
      expect(build_response).to receive(:failed).with('octocat', 'hello-world').and_return([build])
      expect(build_response).to receive(operation).with('octocat', 'hello-world', 99).and_return(build)

      described_class.start([command, *project_args, '--last', '--build=42'])
    end

    it "rejects an invalid build option before looking up the last failed build for #{command}" do
      expect(build_response).not_to receive(:failed)
      expect do
        expect do
          described_class.start([command, *project_args, '--last', '--build=42.5'])
        end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(error_output).to_stderr
    end
  end
end
