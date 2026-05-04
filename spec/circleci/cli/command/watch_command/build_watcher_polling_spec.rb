# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildWatcher, type: :command do
  let(:thread) { instance_double(Thread, kill: nil) }
  let(:step_hash) do
    lambda do |name:, type:, status:, index: 0, step: 0|
      action = { 'type' => type, 'name' => name, 'status' => status, 'index' => index, 'step' => step }
      action['end_time'] = '2024-01-01T00:00:00Z' unless status == 'running'

      { 'name' => name, 'actions' => [action] }
    end
  end
  let(:build_response) do
    lambda do |steps|
      CircleCI::CLI::Response::Build.new(
        'username' => 'user',
        'reponame' => 'repo',
        'status' => 'running',
        'build_num' => 1234,
        'branch' => 'main',
        'author_name' => 'owner',
        'subject' => 'Commit',
        'build_time_millis' => 1000,
        'start_time' => 100_000,
        'steps' => steps
      )
    end
  end
  let(:build) { build_response.call(initial_steps) }

  before do
    stub_const('CircleCI::CLI::Command::BuildWatcher::HTTPClient', CircleCI::CLI::Networking::HTTPClient)
  end

  describe '#start' do
    let(:initial_steps) { [step_hash.call(name: 'Build', type: 'build', status: 'success')] }
    let(:watcher) { described_class.new(build, verbose: true) }
    let(:updated_build) do
      build_response.call(
        [
          step_hash.call(name: 'Build', type: 'build', status: 'success'),
          step_hash.call(name: 'Test', type: 'test', status: 'running', index: 1, step: 2)
        ]
      )
    end
    let(:shell) { instance_double(Thor::Shell::Basic, say: nil) }
    let(:response) { instance_double('response', body: 'step output') }
    let(:url) { 'https://circleci.com/api/private/output/raw/github/user/repo/1234/output/1/2' }

    it 'prints new verbose steps and streams their output' do
      allow(Thread).to receive(:new) do |&block|
        block.call
        thread
      rescue Interrupt
        thread
      end
      allow(watcher).to receive(:sleep).with(1).and_raise(Interrupt)
      allow(watcher).to receive(:say)
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get).and_return(response)
      allow(Thor::Shell::Basic).to receive(:new).and_return(shell)

      watcher.start

      expect(watcher).to have_received(:say).with(a_string_including('| Test'))
      expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:get).with(url, 'Range' => 'bytes=0-')
      expect(shell).to have_received(:say).with('step output', nil, false)
    end
  end

  describe '#update_build' do
    let(:initial_steps) { [step_hash.call(name: 'Build', type: 'build', status: 'success')] }
    let(:watcher) { described_class.new(build, verbose: false) }
    let(:updated_build) { build_response.call([step_hash.call(name: 'Build', type: 'build', status: 'failed')]) }

    it 'prints failed statuses and replays buffered output' do
      watcher.instance_variable_get(:@messages)['Build'] << 'captured output'
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      allow(watcher).to receive(:puts)
      allow(watcher).to receive(:say)

      watcher.send(:update_build)

      expect(watcher).to have_received(:puts).with("\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_red('Build')}")
      expect(watcher).to have_received(:say).with('captured output')
    end

    it 'prints new step statuses for success, failure, and in-progress steps' do
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(
        build_response.call(
          [
            step_hash.call(name: 'Build', type: 'build', status: 'success'),
            step_hash.call(name: 'Test', type: 'test', status: 'failed', index: 1, step: 2),
            step_hash.call(name: 'Deploy', type: 'deploy', status: 'running', index: 2, step: 3)
          ]
        )
      )
      allow(watcher).to receive(:puts)

      watcher.instance_variable_set(:@steps, [])
      watcher.send(:update_build)

      expect(watcher).to have_received(:puts).with("\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Build')}")
      expect(watcher).to have_received(:puts).with("\e[2K\r#{CircleCI::CLI::Printer.colorize_red('Test')}")
      expect(watcher).to have_received(:puts).with('Deploy')
    end

    it 'replaces a running step with a success status line' do
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(
        build_response.call([step_hash.call(name: 'Build', type: 'build', status: 'success')])
      )
      allow(watcher).to receive(:puts)

      watcher.instance_variable_set(
        :@steps,
        [build_response.call([step_hash.call(name: 'Build', type: 'build', status: 'running')]).steps.first]
      )
      watcher.send(:update_build)

      expect(watcher).to have_received(:puts).with(
        "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Build')}"
      )
    end
  end

  describe '#update_actions' do
    let(:initial_steps) { [] }
    let(:watcher) { described_class.new(build, verbose: false) }
    let(:current_step) do
      build_response.call(
        [step_hash.call(name: 'Test', type: 'test', status: 'running', index: 1, step: 2)]
      ).steps.first
    end
    let(:url) { 'https://circleci.com/api/private/output/raw/github/user/repo/1234/output/1/2' }

    it 'buffers output and skips empty response bodies' do
      watcher.instance_variable_set(:@current_step, current_step)
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get)
        .and_return(instance_double('response', body: 'step output'), instance_double('response', body: ''))

      watcher.send(:update_actions)
      watcher.send(:update_actions)

      expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:get).with(url, 'Range' => 'bytes=0-')
      expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:get).with(url, 'Range' => 'bytes=11-')
      expect(watcher.instance_variable_get(:@messages)['Test']).to eq(['step output'])
    end
  end
end
