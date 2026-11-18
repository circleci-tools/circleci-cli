# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildWatcher, type: :command do
  let(:thread) { instance_double(Thread, kill: nil, join: nil) }
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
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get_raw).and_return(response)
      allow(Thor::Shell::Basic).to receive(:new).and_return(shell)

      watcher.start

      expect(watcher).to have_received(:say).with(a_string_including('| Test'))
      expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:get_raw).with(url, 'Range' => 'bytes=0-')
      expect(shell).to have_received(:say).with('step output', nil, false)
    end
  end

  describe '#update_build' do
    let(:initial_steps) { [step_hash.call(name: 'Build', type: 'build', status: 'success')] }
    let(:watcher) { described_class.new(build, verbose: false) }

    context 'with many unchanged steps' do
      let(:initial_steps) do
        Array.new(100) { |index| step_hash.call(name: "Step #{index}", type: 'test', status: 'success') }
      end
      let(:updated_build) { build_response.call(initial_steps) }

      it 'reads previous names and materializes incoming steps once without printing transitions' do
        previous_steps = build.steps
        allow(build).to receive(:steps).and_return(previous_steps)
        allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
        previous_steps.each { |step| expect(step).to receive(:name).once.and_call_original }
        expect(updated_build).to receive(:steps).once.and_call_original
        expect(watcher).not_to receive(:puts)
        expect(watcher).not_to receive(:say)

        watcher.send(:update_build)
      end
    end

    context 'when previous steps with the same name have different statuses' do
      let(:initial_steps) do
        [
          step_hash.call(name: 'Build', type: 'build', status: 'success'),
          step_hash.call(name: 'Build', type: 'build', status: 'failed'),
          step_hash.call(name: 'Test', type: 'test', status: 'success'),
          step_hash.call(name: 'Test', type: 'test', status: 'success')
        ]
      end
      let(:updated_build) { build_response.call(initial_steps) }

      it 'prints a transition for each step with a same-name predecessor in a different status' do
        allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
        allow(watcher).to receive(:puts)

        watcher.send(:update_build)

        expect(watcher).to have_received(:puts).exactly(2).times
        expect(watcher).to have_received(:puts).with(
          "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Build')}"
        ).once
        expect(watcher).to have_received(:puts).with(
          "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_red('Build')}"
        ).once
      end
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
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get_raw)
        .and_return(instance_double('response', body: 'step output'), instance_double('response', body: ''))

      watcher.send(:update_actions)
      watcher.send(:update_actions)

      expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:get_raw).with(url, 'Range' => 'bytes=0-')
      expect(CircleCI::CLI::Networking::HTTPClient).to have_received(:get_raw).with(url, 'Range' => 'bytes=11-')
      expect(watcher.instance_variable_get(:@messages).size).to eq(1)
    end
  end

  describe 'buffered step output' do
    let(:initial_steps) { [step_hash.call(name: 'Test', type: 'test', status: 'running')] }
    let(:watcher) { described_class.new(build) }
    let(:messages) { watcher.instance_variable_get(:@messages) }
    let(:first_chunk) { 'x' * (192 * 1024) }
    let(:second_chunk) { 'y' * (128 * 1024) }
    let(:last_chunk) { "last\n" }

    before do
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(build)
      allow(watcher).to receive(:puts)
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get_raw).and_return(
        instance_double('response', body: first_chunk),
        instance_double('response', body: second_chunk),
        instance_double('response', body: last_chunk)
      )
      watcher.send(:update_build)
      watcher.send(:update_actions)
      expect(messages.values.first.instance_variable_get(:@file)).to be_nil
      watcher.send(:update_actions)
      watcher.send(:update_actions)
    end

    after { watcher.close }

    it 'replays all collected chunks once after failure and removes the spill file' do
      path = messages.values.first.instance_variable_get(:@file).path
      expect(messages.values.first.instance_variable_get(:@memory)).to be_nil
      finish_step('failed')

      expect do
        watcher.send(:update_build)
        watcher.send(:update_build)
      end.to output("#{first_chunk}\n#{second_chunk}\n#{last_chunk}").to_stdout
      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    it 'discards output and removes the spill file after success' do
      path = messages.values.first.instance_variable_get(:@file).path
      finish_step('success')

      expect { watcher.send(:update_build) }.not_to output.to_stdout
      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    it 'removes an active step spill file when closed' do
      path = messages.values.first.instance_variable_get(:@file).path

      watcher.close

      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    it 'removes the spill file if the final build refresh fails' do
      path = messages.values.first.instance_variable_get(:@file).path
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_raise(IOError)

      expect { watcher.stop('failed') }.to raise_error(IOError)
      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    def finish_step(status)
      finished = build_response.call([step_hash.call(name: 'Test', type: 'test', status: status)])
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(finished)
    end
  end
end
