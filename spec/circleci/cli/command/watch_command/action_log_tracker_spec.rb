# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::ActionLogTracker do
  let(:build) do
    instance_double(CircleCI::CLI::Response::Build, username: 'user', reponame: 'repo', build_number: 1234)
  end
  let(:session) { instance_double(CircleCI::CLI::Networking::HTTPClient::Session) }
  let(:log_sessions) { [session] }
  let(:messages) { {} }
  let(:captured_output) { +'' }
  let(:verbose) { false }
  let(:tracker) do
    described_class.new(
      build,
      verbose:,
      log_sessions:,
      messages:,
      output: ->(chunk) { captured_output << chunk }
    )
  end

  def action(index:, step:, status:, end_time: nil)
    instance_double(
      CircleCI::CLI::Response::Action,
      identity: [index, step],
      status:,
      end_time:,
      running?: end_time.nil? && status != 'not_run',
      skipped?: status == 'not_run',
      failed?: %w[failed timedout].include?(status)
    )
  end

  def expect_output_response(path, *chunks)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body) { |&read_chunk| chunks.each(&read_chunk) }
    url = "https://circleci.com/api/private/output/raw/github/user/repo/1234/output/#{path}"
    expect(session).to receive(:get_raw).with(url, { 'Range' => 'bytes=0-' }).and_yield(response)
  end

  describe '#retain_output and #close' do
    it 'buffers a chunk per action identity and clears it on close' do
      tracker.retain_output([0, 1], "hello\n")

      expect(messages[[0, 1]]).to be_a(CircleCI::CLI::Command::StepLog)
      expect(messages[[0, 1]].bytesize).to eq(6)

      tracker.close

      expect(messages).to be_empty
    end
  end

  describe '#finish_action_logs' do
    it 'replays a failed action log once and removes it from messages' do
      tracker.retain_output([0, 1], "boom\n")
      step = instance_double(
        CircleCI::CLI::Response::Step,
        status: 'failed',
        actions: [action(index: 0, step: 1, status: 'failed', end_time: 'now')]
      )

      expect { tracker.finish_action_logs(step) }.to output("boom\n").to_stdout
      expect(messages).to be_empty
    end

    it 'discards a successful action log without printing it' do
      tracker.retain_output([0, 1], "ok\n")
      step = instance_double(
        CircleCI::CLI::Response::Step,
        status: 'success',
        actions: [action(index: 0, step: 1, status: 'success', end_time: 'now')]
      )

      expect { tracker.finish_action_logs(step) }.not_to output.to_stdout
      expect(messages).to be_empty
    end

    it 'keeps a buffered log for a failed action that is still running' do
      tracker.retain_output([0, 1], "partial\n")
      step = instance_double(
        CircleCI::CLI::Response::Step,
        status: 'running',
        actions: [action(index: 0, step: 1, status: 'failed', end_time: nil)]
      )

      tracker.finish_action_logs(step)

      expect(messages).to have_key([0, 1])
    end
  end

  describe '#refresh_action_outputs and #update_actions' do
    context 'with verbose output' do
      let(:verbose) { true }

      it 'streams a tracked running action immediately' do
        expect_output_response('0/1', "hello\n")

        tracker.refresh_action_outputs([action(index: 0, step: 1, status: 'running')], continuing: true)
        tracker.update_actions

        expect(captured_output).to eq("hello\n")
      end
    end

    context 'without verbose output' do
      it 'buffers a tracked running action until it finishes' do
        expect_output_response('0/1', "hello\n")

        tracker.refresh_action_outputs([action(index: 0, step: 1, status: 'running')], continuing: true)
        tracker.update_actions

        expect(captured_output).to be_empty
        expect(messages[[0, 1]].bytesize).to eq(6)
      end
    end

    it 'skips a skipped action entirely' do
      tracker.refresh_action_outputs([action(index: 0, step: 1, status: 'not_run')], continuing: true)
      tracker.update_actions

      expect(captured_output).to be_empty
    end
  end

  describe '#clear_actions' do
    it 'stops tracking previously observed actions' do
      tracker.refresh_action_outputs([action(index: 0, step: 1, status: 'running')], continuing: true)

      tracker.clear_actions
      tracker.update_actions

      expect(captured_output).to be_empty
    end
  end

  describe '#print_completed_outputs' do
    it 'reads and prints a completed action that matches the log filter' do
      expect_output_response('0/1', "done\n")
      step = instance_double(
        CircleCI::CLI::Response::Step,
        actions: [action(index: 0, step: 1, status: 'failed', end_time: 'now')]
      )

      tracker.print_completed_outputs(step, stopping: false)

      expect(captured_output).to eq("done\n")
    end

    it 'skips a completed action that does not match the log filter' do
      step = instance_double(
        CircleCI::CLI::Response::Step,
        actions: [action(index: 0, step: 1, status: 'success', end_time: 'now')]
      )

      tracker.print_completed_outputs(step, stopping: false)

      expect(captured_output).to be_empty
    end
  end
end
