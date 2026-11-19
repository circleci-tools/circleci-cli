# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::WatchCommand, type: :command do
  let(:options) { OpenStruct.new(project: 'user/repo', branch: 'main', user: 'octocat', verbose: true) }

  let(:session) { described_class.new(options, repository) }

  describe '.run' do
    let(:repository) { double('repository') }
    let(:client) { double('client', connect: nil, bind: nil, unsubscribe: nil, disconnect: nil) }
    let(:account) { double('account', pusher_id: 'pusher-id') }
    let(:config) { Struct.new(:token).new }

    before do
      allow(CircleCi).to receive(:configure).and_yield(config)
      allow(ENV).to receive(:fetch).and_call_original
      allow(CircleCI::CLI::Response::Account).to receive(:me).and_return(account)
      allow(repository).to receive(:builds_to_show).and_return([])
      allow(session).to receive(:sleep).with(1).and_raise(Interrupt)
      allow(described_class).to receive(:new).with(options, repository).and_return(session)
      allow(described_class).to receive(:say)
      allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
    end

    it 'initializes dependencies and closes the watcher and client on interrupt' do
      watcher = instance_double(CircleCI::CLI::Command::BuildWatcher)
      allow(session).to receive(:start_watcher_if_needed) { session.instance_variable_set(:@build_watcher, watcher) }

      expect(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).once.and_return('env-token')
      expect(described_class).not_to receive(:ask)
      expect(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new)
        .with(token: 'env-token').and_return(client)

      expect(CircleCI::CLI::Command::BuildRepository).to receive(:new)
        .with('user', 'repo', branch: 'main', user: 'octocat')
      expect(client).to receive(:connect).ordered
      expect(client).to receive(:bind).with('private-pusher-id', 'call').ordered
      expect(watcher).to receive(:close).ordered
      expect(client).to receive(:unsubscribe).with('private-pusher-id').ordered
      expect(client).to receive(:disconnect).ordered
      expect(described_class).to receive(:say).with('Exited')

      described_class.run(options)

      expect(config.token).to eq('env-token')
    end

    it 'releases the subscription and client when binding fails after connecting' do
      allow(described_class).to receive(:setup_token).and_return('token')
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client)
      expect(client).to receive(:connect).ordered
      expect(client).to receive(:bind).with('private-pusher-id', 'call').ordered.and_raise('bind failed')
      expect(client).to receive(:unsubscribe).with('private-pusher-id').ordered
      expect(client).to receive(:disconnect).ordered

      expect { described_class.run(options) }.to raise_error('bind failed')
    end

    it 'prompts once and passes the same token to CircleCI and Pusher' do
      expect(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).once.and_return(nil)
      expect(described_class).to receive(:ask).with('Circle CI token ? :').once.and_return('prompted-token')
      expect(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new)
        .with(token: 'prompted-token').and_return(client)

      described_class.run(options)

      expect(config.token).to eq('prompted-token')
    end
  end

  describe 'account notifications' do
    let(:repository) { CircleCI::CLI::Command::BuildRepository.new('user', 'repo', branch: 'main', user: 'octocat') }
    let(:client) { double('client', connect: nil, unsubscribe: nil, disconnect: nil) }
    let(:account) { double('account', pusher_id: 'pusher-id') }
    let(:running_build) do
      double('running build', build_number: 42, branch: 'main', user: 'octocat', running?: true, finished?: false)
    end
    let(:finished_build) { double('finished build', build_number: 42, finished?: true, status: 'success') }
    let(:watcher) { double('watcher', build: running_build) }

    before do
      allow(described_class).to receive(:setup_token)
      allow(described_class).to receive(:say)
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client)
      allow(CircleCI::CLI::Response::Account).to receive(:me).and_return(account)
    end

    it 'ignores a retained callback from a previous watch invocation' do
      builds = CircleCI::CLI::Response::Build
      allow(builds).to receive(:all).with('user', 'repo').and_return([])
      allow(builds).to receive(:all).with('user', 'other').and_return([])
      other_options = options.dup
      other_options.project = 'user/other'
      other_client = double('other client', connect: nil, unsubscribe: nil, disconnect: nil)
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client, other_client)

      previous_callback = nil
      expect(client).to receive(:bind).with('private-pusher-id', 'call') do |*_, &callback|
        previous_callback = callback
      end
      expect(other_client).to receive(:bind).with('private-pusher-id', 'call')
      ticks = 0
      allow_any_instance_of(described_class).to receive(:sleep).with(1) do
        ticks += 1
        raise Interrupt unless ticks == 2

        previous_callback.call
      end
      expect(builds).not_to receive(:branch)

      described_class.run(options)
      described_class.run(other_options)

      expect(ticks).to eq(3)
    end

    it 'coalesces a burst and refreshes again for a notification received during the request' do
      allow(CircleCI::CLI::Response::Build).to receive(:all).with('user', 'repo').and_return([])
      allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
      allow(described_class).to receive(:new).with(options, repository).and_return(session)
      allow(CircleCI::CLI::Command::BuildWatcher).to receive(:new).with(running_build, verbose: true).and_return(watcher)

      notify = nil
      expect(client).to receive(:bind).with('private-pusher-id', 'call') { |*_, &callback| notify = callback }
      expect(session).to receive(:sleep).with(1).ordered { 100.times { notify.call } }
      expect(CircleCI::CLI::Response::Build).to receive(:branch).with('user', 'repo', 'main').ordered do
        notify.call
        [running_build]
      end
      expect(watcher).to receive(:start).ordered
      expect(session).to receive(:sleep).with(1).ordered
      expect(CircleCI::CLI::Response::Build).to receive(:branch).with('user', 'repo', 'main').ordered
        .and_return([finished_build])
      expect(watcher).to receive(:stop).with('success').ordered
      expect(session).to receive(:sleep).with(1).ordered
      expect(session).to receive(:sleep).with(1).ordered.and_raise(Interrupt)

      described_class.run(options)
    end
  end

  describe 'a watched build outside the recent-build window' do
    it 'keeps watching while running, reports completion once, and starts the next build' do
      response = CircleCI::CLI::Response::Build
      first = response.new('username' => 'user', 'reponame' => 'repo', 'build_num' => 1, 'status' => 'running')
      second = response.new('username' => 'user', 'reponame' => 'repo', 'build_num' => 2, 'status' => 'running')
      finished = response.new('username' => 'user', 'reponame' => 'repo', 'build_num' => 1, 'status' => 'success')
      allow(response).to receive(:all).with('user', 'repo').and_return([first], [second])
      allow(response).to receive(:get).with('user', 'repo', 1).and_return(first, finished)
      repository = CircleCI::CLI::Command::BuildRepository.new('user', 'repo')
      watcher_class = CircleCI::CLI::Command::BuildWatcher
      first_watcher = watcher_class.new(first)
      second_watcher = watcher_class.new(second)
      allow(first_watcher).to receive(:poll_build)
      allow(second_watcher).to receive(:poll_build)
      allow(watcher_class).to receive(:new).with(first, verbose: true).and_return(first_watcher)
      allow(watcher_class).to receive(:new).with(second, verbose: true).and_return(second_watcher)
      session = described_class.new(options, repository)

      expect(first_watcher).to receive(:puts).with(a_string_including('Start watching user/repo #1')).ordered
      expect(first_watcher).to receive(:puts).with(a_string_including('user/repo #1 has succeeded!')).once.ordered
      expect(second_watcher).to receive(:puts).with(a_string_including('Start watching user/repo #2')).ordered
      expect(session).not_to receive(:puts)

      session.send(:start_watcher_if_needed)
      repository.update
      first_watcher.send(:update_build)
      session.send(:stop_existing_watcher_if_needed)
      session.send(:start_watcher_if_needed)
      expect(session.instance_variable_get(:@build_watcher)).to eq(first_watcher)

      first_watcher.send(:update_build)
      2.times do
        session.send(:stop_existing_watcher_if_needed)
        session.send(:start_watcher_if_needed)
      end
      expect(session.instance_variable_get(:@build_watcher)).to eq(second_watcher)
    end
  end

  describe '#stop_existing_watcher_if_needed' do
    let(:build) { double('build', build_number: 42) }
    let(:watcher) { double('watcher', build:) }
    let(:repository) { double('repository') }
    let(:finished_build) { double('finished_build', build_number: 42, finished?: true, status: 'success') }

    it 'stops the current watcher when the tracked build has finished' do
      session.instance_variable_set(:@build_watcher, watcher)

      expect(repository).to receive(:build_for).with(42, recent_only: true).and_return(finished_build)
      expect(watcher).to receive(:stop).with('success')
      expect(repository).to receive(:mark_as_shown).with(42)

      session.send(:stop_existing_watcher_if_needed)

      expect(session.instance_variable_get(:@build_watcher)).to be_nil
    end
  end

  describe '#start_watcher_if_needed' do
    let(:waiting_build) { double('waiting_build', finished?: false, running?: false) }
    let(:running_build) { double('running_build', finished?: false, running?: true, build_number: 42) }
    let(:repository) { double('repository') }
    let(:build_watcher) { double('build_watcher', start: nil) }

    it 'starts a watcher for the first running build that has not been shown' do
      allow(session).to receive(:show_interrupted_build_results)
      allow(CircleCI::CLI::Command::BuildWatcher).to receive(:new).and_return(build_watcher)

      expect(repository).to receive(:builds_to_show).and_return([waiting_build, running_build])
      expect(session).to receive(:show_interrupted_build_results)
      expect(repository).to receive(:watch).with(42).and_return(running_build)
      expect(CircleCI::CLI::Command::BuildWatcher).to receive(:new)
        .with(running_build, verbose: true)
      expect(build_watcher).to receive(:start)

      session.send(:start_watcher_if_needed)

      expect(session.instance_variable_get(:@build_watcher)).to eq(build_watcher)
    end

    it 'prints a newly completed build only once when no live build is available' do
      build_response = CircleCI::CLI::Response::Build
      finished_build = build_response.new(
        'username' => 'user', 'reponame' => 'repo', 'build_num' => 42, 'status' => 'success'
      )
      allow(build_response).to receive(:all).with('user', 'repo').and_return([], [finished_build])
      real_repository = CircleCI::CLI::Command::BuildRepository.new('user', 'repo')
      real_repository.update
      session = described_class.new(options, real_repository)
      expect(build_response).to receive(:get).with('user', 'repo', 42).once.and_return(finished_build)
      expect(CircleCI::CLI::Command::BuildWatcher).not_to receive(:new)

      result = 'Result of user/repo #42 completed in background'
      expected_output = satisfy('print the completed build once') { |output| output.scan(result).size == 1 }
      expect do
        2.times { session.send(:start_watcher_if_needed) }
      end.to output(expected_output).to_stdout
    end

    it 'processes pending completions when there is no running build' do
      finished_build = double('finished_build', finished?: true)

      expect(repository).to receive(:builds_to_show).and_return([finished_build])
      expect(session).to receive(:show_interrupted_build_results)
      expect(CircleCI::CLI::Command::BuildWatcher).not_to receive(:new)

      session.send(:start_watcher_if_needed)
    end
  end

  describe '#show_interrupted_build_results' do
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
    let(:step_printer) { double('step_printer', to_s: 'step output <%= "log" %>') }

    it 'prints finished background builds and marks them as shown' do
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(response_build)
      allow(CircleCI::CLI::Printer::StepPrinter).to receive(:new).and_return(step_printer)

      expect(repository).to receive(:builds_to_show).and_return([running_build, finished_build])
      expect(CircleCI::CLI::Response::Build).to receive(:get).with('user', 'repo', 42)
      expect(CircleCI::CLI::Printer::BuildPrinter).to receive(:header_for)
        .with(finished_build, a_string_including('Result of user/repo #42 completed in background'))
        .and_return('header output <%= "metadata" %>')
      expect(CircleCI::CLI::Printer::StepPrinter).to receive(:new).with(%w[step], pretty: false)
      expect(repository).to receive(:mark_as_shown).with(42)

      expect { session.send(:show_interrupted_build_results) }
        .to output("header output <%= \"metadata\" %>\nstep output <%= \"log\" %>\n").to_stdout
    end
  end
end
