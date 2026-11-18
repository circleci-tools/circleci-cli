# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::WatchCommand, type: :command do
  let(:options) { OpenStruct.new(project: 'user/repo', branch: 'main', user: 'octocat', verbose: true) }

  around do |example|
    state = %i[@options @repository @client @build_watcher @refresh_lock @refresh_pending].to_h do |ivar|
      [ivar, described_class.instance_variable_get(ivar)]
    end

    example.run
  ensure
    state.each { |ivar, value| described_class.instance_variable_set(ivar, value) }
  end

  describe '.run' do
    let(:repository) { double('repository') }
    let(:client) { double('client', connect: nil) }

    it 'initializes dependencies and exits on interrupt' do
      allow(described_class).to receive(:setup_token)
      allow(described_class).to receive(:bind_status_event)
      allow(described_class).to receive(:stop_existing_watcher_if_needed)
      allow(described_class).to receive(:start_watcher_if_needed)
      allow(described_class).to receive(:sleep).with(1).and_raise(Interrupt)
      allow(described_class).to receive(:say)
      allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client)

      expect(CircleCI::CLI::Command::BuildRepository).to receive(:new)
        .with('user', 'repo', branch: 'main', user: 'octocat')
      expect(client).to receive(:connect)
      expect(described_class).to receive(:bind_status_event)
      expect(described_class).to receive(:stop_existing_watcher_if_needed)
      expect(described_class).to receive(:start_watcher_if_needed)
      expect(described_class).to receive(:say).with('Exited')

      described_class.run(options)
    end
  end

  describe 'account notifications' do
    let(:client) { double('client') }
    let(:account) { double('account', pusher_id: 'pusher-id') }
    let(:running_build) do
      double('running build', build_number: 42, branch: 'main', user: 'octocat', running?: true, finished?: false)
    end
    let(:finished_build) { double('finished build', build_number: 42, finished?: true, status: 'success') }
    let(:watcher) { double('watcher', build: running_build) }

    it 'coalesces a burst and refreshes again for a notification received during the request' do
      allow(described_class).to receive(:setup_token)
      allow(described_class).to receive(:say)
      allow(client).to receive(:connect)
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client)
      allow(CircleCI::CLI::Response::Account).to receive(:me).and_return(account)
      allow(CircleCI::CLI::Response::Build).to receive(:all).with('user', 'repo').and_return([])
      allow(CircleCI::CLI::Command::BuildWatcher).to receive(:new).with(running_build, verbose: true).and_return(watcher)

      notify = nil
      expect(client).to receive(:bind).with('private-pusher-id', 'call') { |*_, &callback| notify = callback }
      expect(described_class).to receive(:sleep).with(1).ordered { 100.times { notify.call } }
      expect(CircleCI::CLI::Response::Build).to receive(:branch).with('user', 'repo', 'main').ordered do
        notify.call
        [running_build]
      end
      expect(watcher).to receive(:start).ordered
      expect(described_class).to receive(:sleep).with(1).ordered
      expect(CircleCI::CLI::Response::Build).to receive(:branch).with('user', 'repo', 'main').ordered
        .and_return([finished_build])
      expect(watcher).to receive(:stop).with('success').ordered
      expect(described_class).to receive(:sleep).with(1).ordered
      expect(described_class).to receive(:sleep).with(1).ordered.and_raise(Interrupt)

      described_class.run(options)
    end
  end

  describe '.stop_existing_watcher_if_needed' do
    let(:build) { double('build', build_number: 42) }
    let(:watcher) { double('watcher', build:) }
    let(:repository) { double('repository') }
    let(:finished_build) { double('finished_build', finished?: true, status: 'success') }

    it 'stops the current watcher when the tracked build has finished' do
      described_class.instance_variable_set(:@repository, repository)
      described_class.instance_variable_set(:@build_watcher, watcher)
      allow(described_class).to receive(:show_interrupted_build_results)

      expect(repository).to receive(:build_for).with(42).and_return(finished_build)
      expect(watcher).to receive(:stop).with('success')
      expect(described_class).to receive(:show_interrupted_build_results)

      described_class.send(:stop_existing_watcher_if_needed)

      expect(described_class.instance_variable_get(:@build_watcher)).to be_nil
    end
  end

  describe '.start_watcher_if_needed' do
    let(:waiting_build) { double('waiting_build', running?: false) }
    let(:running_build) { double('running_build', running?: true, build_number: 42) }
    let(:repository) { double('repository') }
    let(:build_watcher) { double('build_watcher', start: nil) }

    it 'starts a watcher for the first running build that has not been shown' do
      described_class.instance_variable_set(:@options, options)
      described_class.instance_variable_set(:@repository, repository)
      described_class.instance_variable_set(:@build_watcher, nil)
      allow(described_class).to receive(:show_interrupted_build_results)
      allow(CircleCI::CLI::Command::BuildWatcher).to receive(:new).and_return(build_watcher)

      expect(repository).to receive(:builds_to_show).and_return([waiting_build, running_build])
      expect(described_class).to receive(:show_interrupted_build_results)
      expect(repository).to receive(:mark_as_shown).with(42)
      expect(CircleCI::CLI::Command::BuildWatcher).to receive(:new)
        .with(running_build, verbose: true)
      expect(build_watcher).to receive(:start)

      described_class.send(:start_watcher_if_needed)

      expect(described_class.instance_variable_get(:@build_watcher)).to eq(build_watcher)
    end
  end

  describe '.show_interrupted_build_results' do
    let(:options) { OpenStruct.new(verbose: false) }
    let(:running_build) { double('running_build', finished?: false) }
    let(:finished_build) do
      double(
        'finished_build',
        finished?: true,
        username: 'user',
        reponame: 'repo',
        build_number: 42,
        project_name: 'user/repo'
      )
    end
    let(:repository) { double('repository') }
    let(:response_build) { double('response_build', steps: %w[step], build_number: 42) }
    let(:step_printer) { double('step_printer', to_s: 'step output') }

    it 'prints finished background builds and marks them as shown' do
      described_class.instance_variable_set(:@options, options)
      described_class.instance_variable_set(:@repository, repository)
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(response_build)
      allow(CircleCI::CLI::Printer::StepPrinter).to receive(:new).and_return(step_printer)
      allow(described_class).to receive(:say)

      expect(repository).to receive(:builds_to_show).and_return([running_build, finished_build])
      expect(CircleCI::CLI::Response::Build).to receive(:get).with('user', 'repo', 42)
      expect(CircleCI::CLI::Printer::BuildPrinter).to receive(:header_for)
        .with(finished_build, a_string_including('Result of user/repo #42 completed in background'))
        .and_return('header output')
      expect(CircleCI::CLI::Printer::StepPrinter).to receive(:new).with(%w[step], pretty: false)
      expect(described_class).to receive(:say).with('header output')
      expect(described_class).to receive(:say).with('step output')
      expect(repository).to receive(:mark_as_shown).with(42)

      described_class.send(:show_interrupted_build_results)
    end
  end
end
