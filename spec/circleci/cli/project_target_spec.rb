# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Runner, type: :command do
  let(:build_response) { CircleCI::CLI::Response::Build }

  def expect_project_error(arguments)
    expect do
      expect do
        described_class.start(arguments)
      end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Project must be in owner/repo format.\n").to_stderr
  end

  {
    'browse' => [[], [:open]],
    'build' => [%w[--last], %i[failed get]],
    'builds' => [[], %i[all branch]],
    'cancel' => [%w[-n 42], [:cancel]],
    'retry' => [%w[--last], %i[failed retry]],
    'watch' => [[], %i[all branch]]
  }.each do |command, (arguments, operations)|
    it "rejects extra path segments before dispatching #{command}" do
      operations.each do |operation|
        expect(operation == :open ? Launchy : build_response).not_to receive(operation)
      end
      expect(CircleCI::CLI::Networking::CircleCIPusherClient).not_to receive(:new) if command == 'watch'

      expect_project_error([command, *arguments, '-p', 'owner/repo/extra'])
    end
  end

  ['', 'owner', '/repo', 'owner/', 'owner//repo', 'owner/repo/', 'owner/..'].each do |project|
    it "rejects #{project.inspect} before opening the browser" do
      expect(Launchy).not_to receive(:open)

      expect_project_error(['browse', "--project=#{project}"])
    end
  end

  [
    'https://github.com/owner/repo/extra.git',
    'ssh://git@github.com:22/owner/repo/extra.git'
  ].each do |remote|
    context "with #{remote} as origin" do
      let(:rugged_response_remote_url) { remote }

      it 'rejects the inferred target before opening the browser' do
        expect(CircleCI::CLI::Command::BrowseCommand).not_to receive(:ask)
        expect(Launchy).not_to receive(:open)

        expect_project_error(%w[browse])
      end
    end
  end

  context 'with a malformed prompted project' do
    let(:mock_rugged_remotes) { [] }
    let(:io_response_project_name) { 'owner/' }

    it 'rejects the answer before cancelling a build' do
      expect(build_response).not_to receive(:cancel)

      expect_project_error(%w[cancel -n 42])
    end
  end
end
