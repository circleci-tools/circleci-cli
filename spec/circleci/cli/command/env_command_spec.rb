# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::EnvCommand, type: :command do
  let(:runner) { CircleCI::CLI::Runner }

  before do
    allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
  end

  describe 'list' do
    it 'prints the masked environment variables for the project' do
      allow_any_instance_of(CircleCi::Project).to receive(:envvar)
        .and_return(circleci_response([{ 'name' => 'FOO', 'value' => 'xxxx1234' }]))

      expect { runner.start(%w[env list -p owner/repo]) }
        .to output(a_string_including('FOO', 'xxxx1234')).to_stdout
    end
  end

  describe 'set' do
    it 'sets the environment variable and confirms it' do
      response = circleci_response('name' => 'FOO', 'value' => 'xxxx1234')
      expect_any_instance_of(CircleCi::Project).to receive(:add_envvar)
        .with(name: 'FOO', value: 'bar').and_return(response)

      expect { runner.start(%w[env set FOO bar -p owner/repo]) }
        .to output("FOO is set for owner/repo.\n").to_stdout
    end
  end

  describe 'delete' do
    it 'deletes the environment variable and confirms it' do
      response = circleci_response('message' => 'ok')
      expect_any_instance_of(CircleCi::Project).to receive(:delete_envvar).with('FOO').and_return(response)

      expect { runner.start(%w[env delete FOO -p owner/repo]) }
        .to output("FOO is deleted for owner/repo.\n").to_stdout
    end
  end

  context 'when the project is omitted' do
    it 'infers the project from the git origin remote' do
      body = [{ 'name' => 'FOO', 'value' => 'xxxx1234' }]
      allow_any_instance_of(CircleCi::Project).to receive(:envvar).and_return(circleci_response(body))
      expect(CircleCi::Project).to receive(:new)
        .with('user', 'local-repository-from-rugged', 'github').and_call_original

      runner.start(%w[env list])
    end
  end

  context 'when the project is malformed' do
    it 'raises before calling the API' do
      expect(CircleCi::Project).not_to receive(:new)

      expect_command_failure(%w[env list -p owner/repo/extra], 'Project must be in owner/repo format.')
    end
  end

  context 'when the API request fails' do
    it 'reports the API error' do
      allow_any_instance_of(CircleCi::Project).to receive(:envvar)
        .and_return(circleci_response({ 'message' => 'Not Found' }, status: '404'))

      expect_command_failure(%w[env list -p owner/repo], 'CircleCI API error (HTTP 404): Not Found')
    end
  end

  def circleci_response(body, status: '200')
    CircleCi::Response.new(double('HTTP response', code: status, body: JSON.generate(body)))
  end

  def expect_command_failure(arguments, message)
    expect do
      expect { runner.start(arguments) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("#{message}\n").to_stderr
  end
end
