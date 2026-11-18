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
        'reponame' => reponame,
        'status' => 'running',
        'build_num' => 1234,
        'branch' => 'main',
        'author_name' => 'Owner <%= "metadata" %>',
        'subject' => 'Commit',
        'build_time_millis' => 1000,
        'start_time' => 100_000,
        'steps' => steps
      )
    end
  end
  let(:reponame) { 'repo' }
  let(:build) { build_response.call(initial_steps) }

  let(:http) { instance_double(Net::HTTP) }
  let(:output_path) { '/api/private/output/raw/github/user/repo/1234/output/1/2' }

  def expect_output_chunk(offset, body)
    expect(http).to receive(:request).ordered do |request|
      expect(request).to be_a(Net::HTTP::Get)
      expect(request.path).to eq(output_path)
      expect(request['Range']).to eq("bytes=#{offset}-")
      output_response(body)
    end
  end

  def output_response(body)
    Net::HTTPPartialContent.new('1.1', '206', 'Partial Content').tap do |response|
      allow(response).to receive(:body).and_return(body)
    end
  end

  describe '#start' do
    let(:initial_steps) { [step_hash.call(name: 'Build', type: 'build', status: 'success')] }
    let(:watcher) { described_class.new(build, verbose: true) }
    let(:updated_build) do
      build_response.call(
        [
          step_hash.call(name: 'Build', type: 'build', status: 'success'),
          step_hash.call(name: step_name, type: 'test', status: 'running', index: 1, step: 2)
        ]
      )
    end
    let(:step_name) { 'Test <%= "step" %>' }

    it 'prints new verbose steps and streams their output' do
      allow(Thread).to receive(:new) do |&block|
        block.call
        thread
      rescue Interrupt
        thread
      end
      polls = 0
      allow(watcher).to receive(:sleep).with(1) do
        polls += 1
        raise Interrupt if polls == 2
      end
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      log_tail = " done <%= \"log\" %>\n"
      expect_output_chunk(0, 'é')
      expect_output_chunk(2, log_tail)

      expect { watcher.start }
        .to output(a_string_including(step_name, "é#{log_tail}", build.author_name)).to_stdout
    end
  end

  describe '#stop' do
    let(:initial_steps) { [] }
    let(:reponame) { 'Repo <%= "metadata" %>' }

    [true, false].each do |verbose|
      it "prints completion metadata literally with verbose=#{verbose}" do
        watcher = described_class.new(build, verbose:)
        allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(build)

        expect { watcher.stop('success') }.to output(a_string_including(build.project_name)).to_stdout
      end
    end
  end

  context 'when an action publishes a final chunk between polls' do
    let(:initial_steps) { [step_hash.call(name: 'Test', type: 'test', status: 'running', index: 1, step: 2)] }
    let(:watcher) { described_class.new(build, verbose: verbose) }
    let(:final_chunk) { "final output\n" }
    let(:url) { 'https://circleci.com/api/private/output/raw/github/user/repo/1234/output/1/2' }
    let(:finished_build) do
      build_response.call([step_hash.call(name: 'Test', type: 'test', status: status, index: 1, step: 2)])
    end

    before do
      allow(Thread).to receive(:new) do |&block|
        catch(:end_polling) { block.call }
        thread
      end
      polls = 0
      allow(watcher).to receive(:sleep).with(1) do
        polls += 1
        throw :end_polling if polls == poll_count
      end
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(build, finished_build)
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get_raw).with(url, { 'Range' => 'bytes=0-' })
        .and_return(output_response("first output\n"))
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get_raw).with(url, { 'Range' => 'bytes=13-' }) do
        if polls >= poll_count - 1
          output_response(final_chunk)
        else
          Net::HTTPRangeNotSatisfiable.new('1.1', '416', 'Range Not Satisfiable')
        end
      end
      allow(watcher).to receive(:notify_started)
    end

    context 'with verbose output' do
      let(:verbose) { true }
      let(:status) { 'success' }
      let(:poll_count) { 6 }

      it 'streams the final chunk on the regular refresh exactly once before completion' do
        shell = instance_double(Thor::Shell::Basic)
        allow(Thor::Shell::Basic).to receive(:new).and_return(shell)
        expect(shell).to receive(:say).with("first output\n", nil, false).once.ordered
        expect(shell).to receive(:say).with(final_chunk, nil, false).once.ordered
        success_table = satisfy('render a success message') { |table| table.to_s.include?('has succeeded!') }
        expect(watcher).to receive(:puts).with(success_table).ordered

        watcher.start
        watcher.stop(status)
      end
    end

    context 'with default output' do
      let(:verbose) { false }
      let(:status) { 'failed' }
      let(:poll_count) { 1 }

      it 'includes the final chunk in the failed-step output when stopped' do
        expect(watcher).to receive(:puts).with(a_string_including('Test')).ordered
        expect(watcher).to receive(:puts).with("first output\n").once.ordered
        expect(watcher).to receive(:puts).with(final_chunk).once.ordered
        expect(watcher).to receive(:puts).with(a_string_including('has failed')).ordered

        watcher.start
        watcher.stop(status)
      end
    end
  end

  describe '#update_build' do
    let(:initial_steps) { [step_hash.call(name: 'Build', type: 'build', status: 'success')] }
    let(:watcher) { described_class.new(build, verbose: false) }
    let(:updated_build) { build_response.call([step_hash.call(name: 'Build', type: 'build', status: 'failed')]) }

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

    it 'prints failed statuses and replays buffered output' do
      log = 'captured output <%= "log" %>'
      watcher.instance_variable_get(:@messages)['Build'] << log
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      status = "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_red('Build')}"

      expect { watcher.send(:update_build) }.to output("#{status}\n#{log}\n").to_stdout
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

    it 'buffers output and skips empty response bodies' do
      watcher.instance_variable_set(:@current_step, current_step)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      expect_output_chunk(0, 'step output')
      expect_output_chunk(11, '')

      watcher.send(:update_actions)
      watcher.send(:update_actions)

      expect(watcher.instance_variable_get(:@messages)['Test']).to eq(['step output'])
    end
  end
end
