# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

describe CircleCI::CLI::Command::WatchCommand, type: :command do
  let(:options) { OpenStruct.new(project: 'user/repo', branch: 'main', user: 'octocat', verbose: true) }

  let(:subscription_success) { 'pusher_internal:subscription_succeeded' }
  let(:session) { described_class.new(options, repository) }

  describe '.run' do
    let(:repository) { double('repository') }
    let(:client) do
      double('client', connect: nil, poll_connection_error: nil, bind: nil, unsubscribe: nil, disconnect: nil)
    end
    let(:account) { double('account', pusher_id: 'pusher-id') }
    let(:config) { Struct.new(:token).new }

    before do
      allow(CircleCi).to receive(:configure).and_yield(config)
      allow(ENV).to receive(:fetch).and_call_original
      allow(CircleCI::CLI::Response::Account).to receive(:me).and_return(account)
      allow(repository).to receive(:refresh_evicted_builds).and_return({})
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
      expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success).ordered
      expect(client).to receive(:connect).ordered
      expect(watcher).to receive(:close).ordered
      expect(client).to receive(:unsubscribe).with('private-pusher-id').ordered
      expect(client).to receive(:disconnect).ordered
      expect(described_class).to receive(:say).with('Exited')

      described_class.run(options)

      expect(config.token).to eq('env-token')
    end

    it 'releases the subscription and client when binding fails' do
      allow(described_class).to receive(:setup_token).and_return('token')
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client)
      expect(client).not_to receive(:connect)
      expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success)
        .ordered.and_raise('bind failed')
      expect(client).to receive(:unsubscribe).with('private-pusher-id').ordered
      expect(client).to receive(:disconnect).ordered

      expect { described_class.run(options) }.to raise_error('bind failed')
    end

    context 'when the Pusher connection drops before teardown' do
      let(:socket) { instance_double(PusherClient::Socket, connect: nil, disconnect: nil) }
      let(:channel) { instance_double(PusherClient::Channel, bind: nil) }

      before do
        allow(described_class).to receive(:setup_token).and_return('token')
        allow(CircleCI::CLI::Networking::VerifiedPusherSocket).to receive(:new).and_return(socket)
        allow(socket).to receive(:subscribe).with('private-pusher-id')
        allow(socket).to receive(:[]).with('private-pusher-id').and_return(channel)
        allow(socket).to receive(:unsubscribe).with('private-pusher-id').and_raise(Errno::EPIPE)
      end

      it 'disconnects the client and exits normally on interrupt' do
        expect(socket).to receive(:disconnect)
        expect(described_class).to receive(:say).with('Exited')

        described_class.run(options)
      end

      it 'preserves the original watch failure' do
        error = RuntimeError.new('watch failed')
        allow(session).to receive(:sleep).with(1).and_raise(error)
        expect(socket).to receive(:disconnect)

        expect { described_class.run(options) }.to raise_error { |raised| expect(raised).to equal(error) }
      end
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

  describe 'the first watch iteration' do
    let(:client) do
      double('client', connect: nil, poll_connection_error: nil, bind: nil, unsubscribe: nil, disconnect: nil)
    end
    let(:account) { double('account', pusher_id: 'pusher-id') }
    let(:watcher) { double('watcher', close: nil) }
    let(:build_response) { CircleCI::CLI::Response::Build }
    let(:branch_build) do
      build_response.new('build_num' => 41, 'branch' => 'main', 'status' => 'running', 'user' => { 'login' => 'octocat' })
    end
    let(:other_build) do
      build_response.new('build_num' => 42, 'branch' => 'other', 'status' => 'running', 'user' => { 'login' => 'octocat' })
    end

    before do
      allow(described_class).to receive(:setup_token)
      allow(CircleCI::CLI::Response::Account).to receive(:me).and_return(account)
      allow_any_instance_of(described_class).to receive(:sleep).with(1).and_raise(Interrupt)
      allow(described_class).to receive(:say)
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client)
    end

    it 'starts watching a running build returned by the selected branch endpoint' do
      finished_build = build_response.new(
        'build_num' => 40, 'branch' => 'main', 'status' => 'success', 'user' => { 'login' => 'octocat' }
      )
      expect(build_response).to receive(:branch).with('user', 'repo', 'main').and_return([branch_build, finished_build])
      expect(build_response).not_to receive(:all)
      expect(build_response).not_to receive(:get)
      expect(CircleCI::CLI::Command::BuildWatcher).to receive(:new).with(branch_build, verbose: true).and_return(watcher)
      expect(watcher).to receive(:start)

      described_class.run(options)
    end

    it 'fetches project-wide builds at startup with --all' do
      options.all = true
      expect(build_response).to receive(:all).with('user', 'repo').and_return([other_build])
      expect(build_response).not_to receive(:branch)
      expect(CircleCI::CLI::Command::BuildWatcher).to receive(:new).with(other_build, verbose: true).and_return(watcher)
      expect(watcher).to receive(:start)

      described_class.run(options)
    end

    it 'picks up a build that starts before subscription activation without a build event' do
      completed_build = build_response.new(
        'build_num' => 40, 'branch' => 'main', 'status' => 'success', 'user' => { 'login' => 'octocat' }
      )
      channel = PusherClient::Channel.new('private-pusher-id')
      recent_builds = [completed_build]
      allow(client).to receive(:bind) do |_, *events, &callback|
        events.each { |event| channel.bind(event, &callback) }
      end
      expect(build_response).to receive(:branch).with('user', 'repo', 'main').ordered { recent_builds }
      expect(client).to receive(:connect).ordered { recent_builds = [branch_build, completed_build] }
      ticks = 0
      allow_any_instance_of(described_class).to receive(:sleep).with(1) do
        ticks += 1
        raise Interrupt if ticks == 2

        channel.dispatch(subscription_success, '{}')
      end
      expect(build_response).to receive(:branch).with('user', 'repo', 'main').ordered do
        expect(ticks).to eq(1)
        recent_builds
      end
      expect(build_response).not_to receive(:get)
      expect(CircleCI::CLI::Command::BuildWatcher).to receive(:new).with(branch_build, verbose: true).and_return(watcher)
      expect(watcher).to receive(:start)

      described_class.run(options)
    end
  end

  describe 'account notifications' do
    let(:repository) { CircleCI::CLI::Command::BuildRepository.new('user', 'repo', branch: 'main', user: 'octocat') }
    let(:client) { double('client', connect: nil, poll_connection_error: nil, unsubscribe: nil, disconnect: nil) }
    let(:account) { double('account', pusher_id: 'pusher-id') }
    let(:running_build) do
      double('running build', build_number: 42, branch: 'main', user: 'octocat', running?: true, finished?: false)
    end
    let(:finished_build) { double('finished build', build_number: 42, finished?: true, status: 'success') }
    let(:watcher) { double('watcher', build: running_build, poll_error: nil) }

    before do
      allow(described_class).to receive(:setup_token)
      allow(described_class).to receive(:say)
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client)
      allow(CircleCI::CLI::Response::Account).to receive(:me).and_return(account)
    end

    it 'reports a fatal detail poll through Thor and closes the watcher without an account event' do
      build_response = CircleCI::CLI::Response::Build
      build = build_response.new(
        'username' => 'user', 'reponame' => 'repo', 'build_num' => 42, 'branch' => 'main',
        'status' => 'running', 'user' => { 'login' => 'octocat' }
      )
      active_watcher = CircleCI::CLI::Command::BuildWatcher.new(build)
      allow(CircleCI::CLI::Command::BuildWatcher).to receive(:new).and_return(active_watcher)
      allow(active_watcher).to receive(:notify_started)
      expect(active_watcher).to receive(:close).once.ordered.and_call_original
      expect(client).to receive(:unsubscribe).with('private-pusher-id').ordered
      expect(client).to receive(:disconnect).ordered
      expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success)
      expect(build_response).to receive(:branch).with('user', 'repo', 'main').once.and_return([build])
      response = CircleCi::Response.new(double('HTTP response', code: '401', body: '{"message":"Unauthorized"}'))
      detail_client = instance_double(CircleCi::Build, get: response)
      expect(CircleCi::Build).to receive(:new).with('user', 'repo', 'github', 42).once.and_return(detail_client)
      watch_session = nil
      allow(described_class).to receive(:new).and_wrap_original do |new_session, *arguments|
        watch_session = new_session.call(*arguments)
        expect(watch_session).to receive(:sleep).with(1).once do
          poller = active_watcher.instance_variable_get(:@build_thread)
          expect(poller.join(5)).to eq(poller)
        end
        watch_session
      end

      expect do
        expect { CircleCI::CLI::Runner.start(%w[watch -p user/repo -b main]) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("CircleCI API error (HTTP 401): Unauthorized\n").to_stderr
      expect(watch_session.instance_variable_get(:@build_watcher)).to be_nil
      expect(active_watcher.instance_variable_get(:@build_thread)).to be_nil
    end

    it 'ignores a retained callback from a previous watch invocation' do
      builds = CircleCI::CLI::Response::Build
      expect(builds).to receive(:branch).with('user', 'repo', 'main').once.and_return([])
      expect(builds).to receive(:branch).with('user', 'other', 'main').once.and_return([])
      other_options = options.dup
      other_options.project = 'user/other'
      other_client = double('other client', connect: nil, poll_connection_error: nil, unsubscribe: nil, disconnect: nil)
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).and_return(client, other_client)

      previous_callback = nil
      expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success) do |*_, &callback|
        previous_callback = callback
      end
      expect(other_client).to receive(:bind).with('private-pusher-id', 'call', subscription_success)
      ticks = 0
      allow_any_instance_of(described_class).to receive(:sleep).with(1) do
        ticks += 1
        raise Interrupt unless ticks == 2

        previous_callback.call
      end

      described_class.run(options)
      described_class.run(other_options)

      expect(ticks).to eq(3)
    end

    it 'refreshes again while the watched build is outside the recent list and its log body is stalled' do
      build_response = CircleCI::CLI::Response::Build
      attributes = {
        'username' => 'user', 'reponame' => 'repo', 'build_num' => 42, 'status' => 'running',
        'branch' => 'main', 'user' => { 'login' => 'octocat' }
      }
      recent_build = build_response.new(attributes)
      action = { 'name' => 'Test', 'type' => 'test', 'status' => 'running', 'index' => 0, 'step' => 0 }
      detail = build_response.new(attributes.merge('steps' => [{ 'name' => 'Test', 'actions' => [action] }]))
      allow(build_response).to receive(:get).with('user', 'repo', 42).and_return(detail)

      reading = Queue.new
      release = Queue.new
      response = Net::HTTPPartialContent.new('1.1', '206', 'Partial Content')
      session_class = CircleCI::CLI::Networking::HTTPClient::Session
      log_session = instance_double(session_class, close: nil)
      allow(session_class).to receive(:new).and_return(log_session)
      allow(log_session).to receive(:get_raw).and_yield(response)
      allow(response).to receive(:read_body) do
        reading << true
        release.pop
      end

      notify = nil
      allow(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success) { |*_, &callback| notify = callback }
      expect(build_response).to receive(:branch).with('user', 'repo', 'main').ordered.and_return([recent_build])
      allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
      allow(described_class).to receive(:new).with(options, repository).and_return(session)
      expect(session).to receive(:sleep).with(1).ordered do
        reading.pop
        notify.call
      end
      expect(build_response).to receive(:branch).with('user', 'repo', 'main').ordered.and_return([])
      expect(detail).to receive(:finished?).ordered.and_call_original
      expect(session).to receive(:sleep).with(1).ordered { notify.call }
      expect(build_response).to receive(:branch).with('user', 'repo', 'main').ordered.and_return([])
      expect(detail).to receive(:finished?).ordered.and_call_original
      expect(session).to receive(:sleep).with(1).ordered.and_raise(Interrupt)

      expect { Timeout.timeout(5) { described_class.run(options) } }.to output(/Start watching/).to_stdout
    end

    it 'keeps watching the last build list and retries a timed-out refresh without another notification' do
      response = CircleCI::CLI::Response::Build
      expect(response).to receive(:branch).with('user', 'repo', 'main').ordered.and_return([running_build])
      allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
      allow(described_class).to receive(:new).with(options, repository).and_return(session)
      allow(CircleCI::CLI::Command::BuildWatcher).to receive(:new).with(running_build, verbose: true).and_return(watcher)
      allow(watcher).to receive(:close)

      notify = nil
      expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success) { |*_, &callback| notify = callback }
      expect(watcher).to receive(:start).ordered
      expect(session).to receive(:sleep).with(1).ordered { notify.call }
      expect(response).to receive(:branch).with('user', 'repo', 'main').ordered.and_raise(Net::ReadTimeout)
      expect(watcher).to receive(:latest_detail).ordered.and_return(nil)
      expect(session).to receive(:sleep).with(1).ordered do
        expect(repository.build_for(42, recent_only: true)).to equal(running_build)
      end
      expect(response).to receive(:branch).with('user', 'repo', 'main').ordered.and_return([finished_build])
      expect(watcher).to receive(:stop).with('success').ordered
      expect(session).to receive(:sleep).with(1).ordered.and_raise(Interrupt)

      described_class.run(options)
    end

    it 'surfaces a permanent API error from an event-triggered refresh' do
      response = CircleCI::CLI::Response::Build
      expect(response).to receive(:branch).with('user', 'repo', 'main').ordered.and_return([])
      allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
      allow(described_class).to receive(:new).with(options, repository).and_return(session)
      expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success).and_yield
      expect(response).to receive(:branch).with('user', 'repo', 'main').ordered
        .and_raise(Thor::Error, 'CircleCI API error (HTTP 401): Unauthorized')

      expect { described_class.run(options) }.to raise_error(Thor::Error, 'CircleCI API error (HTTP 401): Unauthorized')
    end

    it 'coalesces a burst and refreshes again for a notification received during the request' do
      expect(CircleCI::CLI::Response::Build).to receive(:branch).with('user', 'repo', 'main').ordered.and_return([])
      allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
      allow(described_class).to receive(:new).with(options, repository).and_return(session)
      allow(CircleCI::CLI::Command::BuildWatcher).to receive(:new).with(running_build, verbose: true).and_return(watcher)

      notify = nil
      expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success) { |*_, &callback| notify = callback }
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

    it 'reports polled completion once after a final detail timeout and starts the next build' do
      response = CircleCI::CLI::Response::Build
      attributes = {
        'username' => 'user', 'reponame' => 'repo', 'branch' => 'main', 'user' => { 'login' => 'octocat' }
      }
      first = response.new(attributes.merge('build_num' => 42, 'status' => 'running'))
      second = response.new(attributes.merge('build_num' => 43, 'status' => 'running'))
      finished = response.new(attributes.merge('build_num' => 42, 'status' => 'success', 'lifecycle' => 'finished'))
      watcher_class = CircleCI::CLI::Command::BuildWatcher
      first_watcher = watcher_class.new(first)
      second_watcher = watcher_class.new(second)
      allow(watcher_class).to receive(:new).with(first, verbose: true).and_return(first_watcher)
      allow(watcher_class).to receive(:new).with(second, verbose: true).and_return(second_watcher)
      allow(first_watcher).to receive(:start) { first_watcher.send(:notify_started) }
      allow(second_watcher).to receive(:poll_build)

      expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success)
      expect(response).to receive(:branch).with('user', 'repo', 'main').once.and_return([first, second])
      allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
      allow(described_class).to receive(:new).with(options, repository).and_return(session)
      expect(response).to receive(:get).with('user', 'repo', 42).exactly(4).times.and_invoke(
        ->(*) { first }, ->(*) { finished }, ->(*) { raise Net::ReadTimeout }, ->(*) { finished }
      )
      expect(session).to receive(:sleep).with(1).twice.ordered { first_watcher.send(:update_build) }
      expect(session).to receive(:sleep).with(1).ordered
      expect(session).to receive(:sleep).with(1).ordered.and_raise(Interrupt)

      result = 'user/repo #42 has succeeded!'
      expected_output = satisfy('report success once before starting the next build') do |output|
        output.scan('Start watching user/repo #42').size == 1 && output.scan(result).size == 1 &&
          output.match?(%r{Start watching user/repo #42.*#{Regexp.escape(result)}.*Start watching user/repo #43}m)
      end
      expect { described_class.run(options) }.to output(expected_output).to_stdout
    end

    {
      'timedout' => 'timed out.',
      'infrastructure_fail' => 'failed due to an infrastructure error.',
      'fixed' => 'has been fixed!'
    }.each do |status, message|
      it "reports #{status} and starts watching the next running build" do
        build_response = CircleCI::CLI::Response::Build
        attributes = {
          'username' => 'user', 'reponame' => 'repo', 'branch' => 'main', 'user' => { 'login' => 'octocat' }
        }
        first_build = build_response.new(attributes.merge('build_num' => 42, 'status' => 'running'))
        next_build = build_response.new(attributes.merge('build_num' => 43, 'status' => 'running'))
        completed_build = build_response.new(attributes.merge(
                                               'build_num' => 42, 'status' => status, 'lifecycle' => 'finished'
                                             ))
        allow(build_response).to receive(:branch).with('user', 'repo', 'main')
          .and_return([first_build], [completed_build, next_build])
          allow(CircleCI::CLI::Command::BuildRepository).to receive(:new).and_return(repository)
          allow(described_class).to receive(:new).with(options, repository).and_return(session)
        expect(build_response).to receive(:get).with('user', 'repo', 42).once.and_return(completed_build)
        allow_any_instance_of(CircleCI::CLI::Command::BuildWatcher).to receive(:start) do |build_watcher|
          build_watcher.send(:notify_started)
        end

        notify = nil
        expect(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success) { |*_, &callback| notify = callback }
        expect(session).to receive(:sleep).with(1).twice.ordered { notify.call }
        expect(session).to receive(:sleep).with(1).ordered.and_raise(Interrupt)

        expect { described_class.run(options) }.to output(
          /Start watching user\/repo #42.*user\/repo #42 #{Regexp.escape(message)}.*Start watching user\/repo #43/m
        ).to_stdout
      end
    end
  end

  describe 'a watched build outside the recent-build window' do
    it 'keeps watching while running, reports completion once, and starts the next build' do
      response = CircleCI::CLI::Response::Build
      first = response.new('username' => 'user', 'reponame' => 'repo', 'build_num' => 1, 'status' => 'running')
      second = response.new('username' => 'user', 'reponame' => 'repo', 'build_num' => 2, 'status' => 'running')
      finished = response.new(
        'username' => 'user', 'reponame' => 'repo', 'build_num' => 1, 'status' => 'timedout', 'lifecycle' => 'finished'
      )
      allow(response).to receive(:all).with('user', 'repo').and_return([first], [second])
      allow(response).to receive(:get).with('user', 'repo', 1).and_return(first, finished)
      repository = CircleCI::CLI::Command::BuildRepository.new('user', 'repo')
      watcher_class = CircleCI::CLI::Command::BuildWatcher
      first_watcher = watcher_class.new(first)
      second_watcher = watcher_class.new(second)
      allow(first_watcher).to receive(:start) { first_watcher.send(:notify_started) }
      allow(second_watcher).to receive(:poll_build)
      allow(watcher_class).to receive(:new).with(first, verbose: true).and_return(first_watcher)
      allow(watcher_class).to receive(:new).with(second, verbose: true).and_return(second_watcher)
      session = described_class.new(options, repository)

      expect(first_watcher).to receive(:puts).with(a_string_including('Start watching user/repo #1')).ordered
      expect(first_watcher).to receive(:puts).with(a_string_including('user/repo #1 timed out.')).once.ordered
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

  describe 'a background build outside the recent-build window' do
    let(:response) { CircleCI::CLI::Response::Build }
    let(:watcher_class) { CircleCI::CLI::Command::BuildWatcher }
    let(:attributes) do
      { 'username' => 'user', 'reponame' => 'repo', 'branch' => 'main', 'user' => { 'login' => 'octocat' } }
    end
    let(:initial_status) { 'running' }
    let(:background) { response.new(attributes.merge('build_num' => 2, 'status' => initial_status)) }

    let(:foreground) { response.new(attributes.merge('build_num' => 1, 'status' => 'running')) }
    let(:repository) do
      allow(response).to receive(:branch).with('user', 'repo', 'main').and_return([foreground, background], [])
      repository = CircleCI::CLI::Command::BuildRepository.new('user', 'repo', branch: 'main', user: 'octocat')
      repository.watch(1)
      repository.update
      repository.mark_as_shown(1)
      repository
    end

    it 'reports a completed build once without starting a watcher' do
      completed = response.new(attributes.merge('build_num' => 2, 'status' => 'success'))
      expect(response).to receive(:get).with('user', 'repo', 2).once.and_return(completed)
      expect(watcher_class).not_to receive(:new)

      result = 'Result of user/repo #2 completed in background'
      expected_output = satisfy('print the completed build once') { |output| output.scan(result).size == 1 }
      expect do
        2.times { session.send(:start_watcher_if_needed) }
      end.to output(expected_output).to_stdout
    end

    context 'when the build is initially waiting' do
      let(:initial_status) { 'not_running' }

      it 'checks again on the next iteration and watches the build when it starts running' do
        running = response.new(attributes.merge('build_num' => 2, 'status' => 'running'))
        watcher = instance_double(watcher_class)
        expect(response).to receive(:get).with('user', 'repo', 2).twice.and_return(background, running)
        expect(watcher_class).to receive(:new).with(running, verbose: true).and_return(watcher)
        expect(watcher).to receive(:start)

        session.send(:start_watcher_if_needed)
        expect(session.instance_variable_get(:@build_watcher)).to be_nil
        session.send(:start_watcher_if_needed)
        expect(session.instance_variable_get(:@build_watcher)).to eq(watcher)
      end
    end
  end

  describe 'background detail requests during watch' do
    let(:response) { CircleCI::CLI::Response::Build }
    let(:attributes) { { 'username' => 'user', 'reponame' => 'repo' } }
    let(:background) { response.new(attributes.merge('build_num' => 1, 'status' => 'not_running')) }
    let(:completed) { response.new(attributes.merge('build_num' => 1, 'status' => 'success')) }
    let(:live) { response.new(attributes.merge('build_num' => 2, 'status' => 'running')) }
    let(:later_completed) { response.new(attributes.merge('build_num' => 3, 'status' => 'success')) }
    let(:repository) { CircleCI::CLI::Command::BuildRepository.new('user', 'repo') }
    let(:client) { double('client', connect: nil, poll_connection_error: nil, unsubscribe: nil, disconnect: nil) }
    let(:watcher_class) { CircleCI::CLI::Command::BuildWatcher }
    let(:watcher) { instance_double(watcher_class, build: live, poll_error: nil, latest_detail: nil, close: nil) }

    before do
      allow(CircleCI::CLI::Response::Account).to receive(:me).and_return(double(pusher_id: 'pusher-id'))
      allow(CircleCI::CLI::Networking::CircleCIPusherClient).to receive(:new).with(token: 'token').and_return(client)
      allow(client).to receive(:bind).with('private-pusher-id', 'call', subscription_success).and_yield
      allow(response).to receive(:all).with('user', 'repo').and_return([background], recent_builds)
    end

    shared_examples 'retrying a background detail request' do
      it 'starts the live build and reports other completions while retrying the timed-out build' do
        expect(response).to receive(:get).with('user', 'repo', 1).ordered.and_raise(Net::ReadTimeout)
        expect(response).to receive(:get).with('user', 'repo', 3).once.ordered.and_return(later_completed)
        expect(watcher_class).to receive(:new).with(live, verbose: true).ordered.and_return(watcher)
        expect(watcher).to receive(:start).ordered
        expect(session).to receive(:sleep).with(1).ordered
        expect(response).to receive(:get).with('user', 'repo', 1).ordered.and_raise(Net::ReadTimeout)
        expect(session).to receive(:sleep).with(1).ordered
        expect(response).to receive(:get).with('user', 'repo', 1).ordered.and_return(completed)
        expect(session).to receive(:sleep).with(1).ordered
        expect(session).to receive(:sleep).with(1).ordered.and_raise(Interrupt)

        results = satisfy('print each background result once in completion order') do |output|
          output.scan(%r{Result of user/repo #(\d+) completed in background}).flatten == %w[3 1]
        end
        expect do
          expect { session.run('token') }.to raise_error(Interrupt)
        end.to output(results).to_stdout
      end

      it 'surfaces a permanent detail failure' do
        error = Thor::Error.new('CircleCI API error (HTTP 401): Unauthorized')
        expect(response).to receive(:get).with('user', 'repo', 1).once.and_raise(error)
        expect(watcher_class).not_to receive(:new)

        expect { session.run('token') }.to raise_error(error)
      end
    end

    context 'when the background build has dropped out of the recent list' do
      let(:recent_builds) { [live, later_completed] }

      include_examples 'retrying a background detail request'
    end

    context 'when the background build finished in the recent list' do
      let(:recent_builds) { [completed, live, later_completed] }

      include_examples 'retrying a background detail request'
    end
  end

  describe '#stop_existing_watcher_if_needed' do
    let(:build) { double('build', build_number: 42) }
    let(:watcher) { double('watcher', build:, poll_error: nil) }
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

    before { allow(repository).to receive(:refresh_evicted_builds).and_return({}) }

    it 'starts a watcher for the first running build that has not been shown' do
      allow(CircleCI::CLI::Command::BuildWatcher).to receive(:new).and_return(build_watcher)

      expect(repository).to receive(:builds_to_show).and_return([waiting_build, running_build])
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
    let(:options) { OpenStruct.new(verbose: verbose) }
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
    let(:step) do
      CircleCI::CLI::Response::Step.new({
        'actions' => [
          { 'name' => 'Setup', 'status' => 'success', 'index' => 0, 'step' => 1,
            'output_url' => 'https://circleci.com/output/setup' },
          { 'name' => 'Test', 'status' => 'failed', 'index' => 1, 'step' => 1,
            'output_url' => 'https://circleci.com/output/test' },
          { 'name' => 'Deploy', 'status' => 'not_run' }
        ]
      })
    end
    let(:response_build) { double('response_build', steps: [step], build_number: 42) }
    let(:verbose) { false }
    let(:builds) { [running_build, finished_build] }

    def log_response(message)
      Net::HTTPOK.new('1.1', '200', 'OK').tap do |response|
        allow(response).to receive(:read_body).and_yield(JSON.generate([{ 'message' => message }]))
      end
    end

    before do
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get_raw)
        .with('https://circleci.com/output/setup').and_yield(log_response("setup log\e[2K"))
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get_raw)
        .with('https://circleci.com/output/test').and_yield(log_response('test log <%= "log" %>'))

      expect(CircleCI::CLI::Printer::BuildPrinter).to receive(:header_for)
        .with(finished_build, a_string_including('Result of user/repo #42 completed in background'))
        .and_return('header output <%= "metadata" %>')
      expect(repository).to receive(:mark_as_shown).with(42)
    end

    it 'prints only failed action logs by default' do
      expect(CircleCI::CLI::Response::Build).to receive(:get).with('user', 'repo', 42).and_return(response_build)
      expect(CircleCI::CLI::Networking::HTTPClient).not_to receive(:get_raw).with('https://circleci.com/output/setup')

      expect { session.send(:show_interrupted_build_results, builds, {}) }
        .to output(satisfy do |output|
          output.include?('header output <%= "metadata" %>') &&
            output.scan('test log <%= "log" %>').size == 1 && !output.include?('setup log')
        end).to_stdout
    end

    it 'preserves the background result when a live step completes afterward' do
      attributes = { 'username' => 'user', 'reponame' => 'repo', 'build_num' => 43 }
      build_class = CircleCI::CLI::Response::Build
      watcher = CircleCI::CLI::Command::BuildWatcher.new(build_class.new(attributes))
      session.instance_variable_set(:@build_watcher, watcher)
      running = { 'name' => 'Live test', 'actions' => [{ 'status' => 'running' }] }
      completed = running.merge('actions' => [{ 'status' => 'success', 'end_time' => '2024-01-01T00:00:00Z' }])
      allow(build_class).to receive(:get).with('user', 'repo', 43).and_return(
        build_class.new(attributes.merge('steps' => [running])),
        build_class.new(attributes.merge('steps' => [completed]))
      )
      completed_line = CircleCI::CLI::Printer.colorize_green('Live test')

      expect do
        watcher.send(:update_build)
        session.send(:show_interrupted_build_results, builds, { 42 => response_build })
        watcher.send(:update_build)
      end.to output(/\ALive test\n.*test log <%= "log" %>\n.*\n#{Regexp.escape(completed_line)}\n\z/m).to_stdout
    ensure
      watcher&.close
    end

    context 'with verbose enabled' do
      let(:verbose) { true }

      it 'prints both successful and failed action logs with control characters escaped' do
        expect(CircleCI::CLI::Response::Build).not_to receive(:get)

        expect { session.send(:show_interrupted_build_results, builds, { 42 => response_build }) }
          .to output(satisfy do |output|
            output.scan('setup log\x1B[2K').size == 1 && output.scan('test log <%= "log" %>').size == 1 &&
              output.include?('Deploy')
          end).to_stdout
      end
    end
  end
end
