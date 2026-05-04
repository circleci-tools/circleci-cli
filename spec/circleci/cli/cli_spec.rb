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

    it 'prints the version' do
      expect { described_class.start(%w[version]) }.to output("#{CircleCI::CLI::VERSION}\n").to_stdout
    end
  end
end
