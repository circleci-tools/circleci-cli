# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'spec_helper'
require 'tmpdir'

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

    {
      'https://GITHUB.COM/user/repository' => 'user/repository',
      'ssh://git@github.com:22/user/example.com.git' => 'user/example.com',
      'ssh://git@ssh.github.com:443/user/example.com.git' => 'user/example.com',
      'https://github.com/user/repository.git.git' => 'user/repository.git'
    }.each do |remote, slug|
      context "with #{remote} as origin" do
        let(:rugged_response_remote_url) { remote }

        it { is_expected.to eq(slug) }
      end
    end

    [
      'git@bitbucket.org:user/repository.git',
      'git@githubXcom:user/repository.git',
      'https://github.com.example.org/user/repository.git',
      'https://github.com@example.org/user/repository.git',
      'https://example.org/https://github.com/user/repository.git',
      'https://github.com:invalid/user/repository.git',
      'https://github.com/user/nested/repository.git',
      'https://github.com/user/repository.git/',
      'https://github.com/user/repository.git?query',
      'ssh://git@github.com/user/repository.git#fragment',
      'ssh://git@github.com/user/..',
      'ssh://git@ssh.github.com/user/repository.git',
      'ssh://git@ssh.github.com:22/user/repository.git',
      'ssh://other@ssh.github.com:443/user/repository.git',
      'https://git@ssh.github.com:443/user/repository.git',
      'ssh://git@ssh.github.com.example.org:443/user/repository.git',
      'git@github.com:user/repository%2Fother.git',
      "git@github.com:user/repository.git\nignored"
    ].each do |remote|
      context "with #{remote.inspect} as origin" do
        let(:rugged_response_remote_url) { remote }

        it { is_expected.to be_nil }
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

  describe 'the executable' do
    [false, true].each do |git_checkout|
      location = git_checkout ? 'a repository without origin' : 'outside Git'

      it "prints the version in #{location}" do
        root = File.expand_path('../../..', __dir__)
        Dir.mktmpdir('cli-startup-', root) do |directory|
          if git_checkout
            repository = Rugged::Repository.init_at(directory)
            tree = Rugged::Tree::Builder.new(repository).write
            signature = { name: 'CLI Test', email: 'cli@example.com', time: Time.now }
            Rugged::Commit.create(repository, tree: tree, parents: [], message: 'Initial commit',
                                              author: signature, committer: signature, update_ref: 'HEAD')
          end

          output, error, status = Open3.capture3(
            RbConfig.ruby, "-I#{root}/lib", "#{root}/exe/circleci-cli", 'version', chdir: directory
          )

          expect(status.success?).to be(true), error
          expect(output).to eq("#{CircleCI::CLI::VERSION}\n")
        end
      end
    end
  end

  describe '.start' do
    {
      cancel: CircleCI::CLI::Command::CancelCommand,
      retry: CircleCI::CLI::Command::RetryCommand
    }.each do |operation, command|
      [
        'https://githubXcom/decoy/repository.git',
        'https://example.org/https://github.com/decoy/repository.git'
      ].each do |remote|
        context "when running #{operation} with #{remote} as origin" do
          let(:rugged_response_remote_url) { remote }

          it 'uses the project entered at the prompt for the build operation' do
            allow(ENV).to receive(:fetch).and_call_original
            allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
            allow(CircleCI::CLI::Response::Project).to receive(:all).and_return([])
            allow(command).to receive(:puts)
            expect(command).to receive(:ask).with('Input user-name/project-name :').and_return('selected/project')
            expect(CircleCI::CLI::Response::Build).to receive(operation).with('selected', 'project', 42)
                                                                       .and_return(double(username: nil))

            described_class.start([operation.to_s, '--build', '42'])
          end
        end
      end
    end

    [
      ['projects', [], CircleCI::CLI::Command::ProjectsCommand, { 'pretty' => true }],
      ['builds', %w[--project octocat/hello-world --branch main], CircleCI::CLI::Command::BuildsCommand,
       { 'project' => 'octocat/hello-world', 'branch' => 'main', 'all' => false, 'pretty' => true }],
      ['build', %w[--project octocat/hello-world --build 42], CircleCI::CLI::Command::BuildCommand,
       { 'project' => 'octocat/hello-world', 'build' => '42', 'last' => false, 'pretty' => true }],
      ['browse', %w[--project octocat/hello-world --build 42], CircleCI::CLI::Command::BrowseCommand,
       { 'project' => 'octocat/hello-world', 'build' => '42' }],
      ['retry', %w[--project octocat/hello-world --build 42], CircleCI::CLI::Command::RetryCommand,
       { 'project' => 'octocat/hello-world', 'build' => '42' }],
      ['cancel', %w[--project octocat/hello-world --build 42], CircleCI::CLI::Command::CancelCommand,
       { 'project' => 'octocat/hello-world', 'build' => '42' }],
      ['watch', %w[--project octocat/hello-world --branch main --user octocat --verbose],
       CircleCI::CLI::Command::WatchCommand,
       { 'project' => 'octocat/hello-world', 'branch' => 'main', 'user' => 'octocat', 'verbose' => true }]
    ].each do |command_name, arguments, command_class, expected_options|
      it "routes #{command_name} to #{command_class}" do
        expect(Rugged::Repository).not_to receive(:new)
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
                                         .and_return(instance_double(Net::HTTPOK, code: '200', body: '[]'))

        described_class.start(['builds', '-p', 'octocat/hello-world', '-b', branch])
        end
      end

    it 'infers the project and branch for builds' do
      allow(mock_rugged_head).to receive(:name).and_return('refs/heads/feature/topic')
      expect(CircleCI::CLI::Command::BuildsCommand).to receive(:run).with(
        hash_including('project' => 'user/local-repository-from-rugged', 'branch' => 'feature/topic')
      )

      described_class.start(%w[builds])
    end

    context 'with a GitHub SSH-over-HTTPS origin' do
      let(:rugged_response_remote_url) { 'ssh://git@ssh.github.com:443/owner/repo.git' }

      it 'requests builds for the inferred project without prompting' do
        allow(CircleCI::CLI::Command::BuildsCommand).to receive(:setup_token)
        expect(CircleCI::CLI::Command::BuildsCommand).not_to receive(:ask)
        expect(CircleCI::CLI::Response::Project).not_to receive(:all)
        expect(CircleCI::CLI::Response::Build).to receive(:branch)
          .with('owner', 'repo', rugged_response_branch_name).and_return([])

        expect { described_class.start(%w[builds]) }.to output.to_stdout
      end
    end

    it 'skips branch inference with --all' do
      expect(Rugged::Repository).not_to receive(:new)
      expect(CircleCI::CLI::Command::BuildsCommand).to receive(:run).with(hash_including('all' => true))

      described_class.start(%w[builds --project octocat/hello-world --all])
    end

    context 'outside Git' do
      before do
        allow(Rugged::Repository).to receive(:new).with('.').and_raise(Rugged::RepositoryError)
      end

      it 'leaves project selection to the command' do
        expect(CircleCI::CLI::Command::BrowseCommand).to receive(:run).with(hash_including('project' => nil))

        described_class.start(%w[browse])
      end

      it 'dispatches builds with an explicit project and no branch' do
        expect(CircleCI::CLI::Command::BuildsCommand).to receive(:run).with(
          hash_including('project' => 'octocat/hello-world', 'branch' => nil)
        )

        described_class.start(%w[builds --project octocat/hello-world])
      end
    end

    it 'leaves the branch unset when HEAD has no commit' do
      allow(mock_rugged_repository).to receive(:head).and_raise(Rugged::ReferenceError)
      expect(CircleCI::CLI::Command::BuildsCommand).to receive(:run).with(hash_including('branch' => nil))

      described_class.start(%w[builds --project octocat/hello-world])
    end

    context 'without an origin remote' do
      let(:mock_rugged_remotes) { [] }

      it 'leaves project selection to the command and still infers the branch' do
        expect(CircleCI::CLI::Command::BuildsCommand).to receive(:run).with(
          hash_including('project' => nil, 'branch' => rugged_response_branch_name)
        )

        described_class.start(%w[builds])
      end

      it 'uses the explicit project' do
        expect(mock_rugged_repository).not_to receive(:remotes)
        expect(CircleCI::CLI::Command::BuildsCommand).to receive(:run).with(
          hash_including('project' => 'octocat/hello-world', 'branch' => rugged_response_branch_name)
        )

        described_class.start(%w[builds --project octocat/hello-world])
      end
    end

    it 'prints the version' do
      expect(Rugged::Repository).not_to receive(:new)
      expect { described_class.start(%w[version]) }.to output("#{CircleCI::CLI::VERSION}\n").to_stdout
    end

    it 'shows usage for the build command' do
      expect { described_class.start(%w[help build]) }
        .to output(/Usage:\n  \S+ build\b.*Show the build result/m).to_stdout
    end
  end
end
