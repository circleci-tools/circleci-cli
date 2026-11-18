# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Runner do
  describe '#project' do
    subject { described_class.project }

    context 'when git repository has a https github remote' do
      let(:rugged_response_remote_url) { 'https://github.com/user/repository.git' }
      it 'extracts the reponame from the origin url' do
        expect(subject).to eq('user/repository')
      end
    end

    context 'when git repository has a github remote' do
      let(:rugged_response_remote_url) { 'git@github.com:user/repository.git' }
      it 'extracts the reponame from the origin url' do
        expect(subject).to eq('user/repository')
      end
    end

    context 'when git repository has a github remote that contains a dot' do
      let(:rugged_response_remote_url) { 'git@github.com:user/example.com.git' }
      it 'extracts the reponame from the origin url, including the dot' do
        expect(subject).to eq('user/example.com')
      end
    end

    context 'when git repository has a non-github remote' do
      let(:rugged_response_remote_url) { 'git@bitbucket.org:user/repository.git' }
      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '#branch_name' do
    subject { described_class.branch_name }

    context 'with a valid current branch' do
      let(:rugged_response_branch_name) { 'branch' }
      let(:rugged_response_is_branch) { true }

      it { is_expected.to eq(rugged_response_branch_name) }
    end

    context 'with no current branch' do
      let(:rugged_response_branch_name) { nil }
      let(:rugged_response_is_branch) { false }

      it { is_expected.to be_nil }
    end
  end

  describe '.start' do
    [
      ['projects', [], CircleCI::CLI::Command::ProjectsCommand, { 'pretty' => true }],
      ['builds', %w[--project octocat/hello-world --branch main], CircleCI::CLI::Command::BuildsCommand,
       { 'project' => 'octocat/hello-world', 'branch' => 'main', 'all' => false, 'pretty' => true }],
      ['build', %w[--project octocat/hello-world --build 42], CircleCI::CLI::Command::BuildCommand,
       { 'project' => 'octocat/hello-world', 'build' => 42, 'last' => false, 'pretty' => true }],
      ['browse', %w[--project octocat/hello-world --build 42], CircleCI::CLI::Command::BrowseCommand,
       { 'project' => 'octocat/hello-world', 'build' => 42 }],
      ['retry', %w[--project octocat/hello-world --build 42], CircleCI::CLI::Command::RetryCommand,
       { 'project' => 'octocat/hello-world', 'build' => 42 }],
      ['cancel', %w[--project octocat/hello-world --build 42], CircleCI::CLI::Command::CancelCommand,
       { 'project' => 'octocat/hello-world', 'build' => 42 }],
      ['watch', %w[--project octocat/hello-world --branch main --user octocat --verbose],
       CircleCI::CLI::Command::WatchCommand,
       { 'project' => 'octocat/hello-world', 'branch' => 'main', 'user' => 'octocat', 'verbose' => true }]
    ].each do |command_name, arguments, command_class, expected_options|
      it "routes #{command_name} to #{command_class}" do
        expect(command_class).to receive(:run) do |options|
          expect(options.to_h.slice(*expected_options.keys)).to eq(expected_options)
        end

        described_class.start([command_name, *arguments])
      end
    end

    [
      ['release#1', 'release%231'],
      ['café', 'caf%C3%A9'],
      ['feature/topic', 'feature%2Ftopic']
    ].each do |branch, encoded_branch|
      it "encodes #{branch} in the builds request" do
        allow(CircleCI::CLI::Command::BuildsCommand).to receive(:setup_token)
        allow(CircleCI::CLI::Command::BuildsCommand).to receive(:say)
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:start).and_yield(http)
        allow_any_instance_of(CircleCi::Project).to receive(:recent_builds_branch).and_call_original
        path = "/api/v1.1/project/github/octocat/hello-world/tree/#{encoded_branch}"
        expect(http).to receive(:request).with(having_attributes(uri: having_attributes(path: path)), nil)
                                         .and_return(instance_double(Net::HTTPOK, body: '[]'))

        described_class.start(['builds', '-p', 'octocat/hello-world', '-b', branch])
      end
    end

    it 'prints the version' do
      expect { described_class.start(%w[version]) }.to output("#{CircleCI::CLI::VERSION}\n").to_stdout
    end
  end
end
