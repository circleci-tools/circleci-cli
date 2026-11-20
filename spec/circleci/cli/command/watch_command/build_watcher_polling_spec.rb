# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

describe CircleCI::CLI::Command::BuildWatcher, type: :command do
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
  let(:step_name) { "Test\r\e[2K" }
  let(:escaped_step_name) { 'Test\x0D\x1B[2K' }
  let(:log_output) { "é first\r\nsecond\r\e[2K\u009B\nthird".b + "\x9D".b }
  let(:escaped_log_output) { "é first\nsecond\\x0D\\x1B[2K\\x9B\nthird\\x9D" }

  let(:http) { instance_double(Net::HTTP) }
  let(:output_path) { '/api/private/output/raw/github/user/repo/1234/output/1/2' }

  before { allow(http).to receive(:max_retries=).with(0) }

  def expect_output_response(offset, *chunks, error: nil, path: output_path)
    expect(http).to receive(:request).ordered do |request, &read_response|
      expect(request).to be_a(Net::HTTP::Get)
      expect(request.path).to eq(path)
      expect(request['Range']).to eq("bytes=#{offset}-")
      response = Net::HTTPPartialContent.new('1.1', '206', 'Partial Content')
      allow(response).to receive(:read_body) do |&read_chunk|
        chunks.each(&read_chunk)
        raise error if error
      end
      read_response.call(response)
    end
  end

  def pause_after_polls(limit)
    waiting = Queue.new
    stop_requested = watcher.instance_variable_get(:@stop_requested)
    polls = 0
    allow(stop_requested).to receive(:pop).with(timeout: 1).and_wrap_original do |pop|
      polls += 1
      yield polls if block_given?
      if polls == limit
        waiting << true
        pop.call
      end
    end
    waiting
  end

  def watch_until(waiting, status)
    watcher.start
    Timeout.timeout(5) { waiting.pop }
    watcher.stop(status)
  ensure
    watcher.close
  end

  describe '#start' do
    let(:initial_steps) { [] }
    let(:watcher) { described_class.new(build, verbose: true) }
    let(:updated_build) do
      build_response.call(
        [
          step_hash.call(name: 'Checkout', type: 'checkout', status: 'success'),
          step_hash.call(name: step_name, type: 'shell', status: 'success'),
          step_hash.call(name: 'Upload', type: 'store_artifacts', status: 'running', index: 1, step: 2),
          step_hash.call(name: 'Deploy', type: 'shell', status: 'running', index: 1, step: 3)
        ]
      )
    end
    let(:step_name) { "Test <%= \"step\" %>\r\e[2K" }
    let(:escaped_step_name) { 'Test <%= "step" %>\x0D\x1B[2K' }

    before do
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
    end

    it 'prints new steps in API order and streams output from the first running step' do
      streamed = pause_after_polls(2)
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      log_tail = " done <%= \"log\" %>\n"
      expect_output_response(0, log_output.byteslice(0, 1), log_output.byteslice(1, 9), log_output.byteslice(10..))
      expect_output_response(log_output.bytesize, log_tail)

      expect_output_response(log_output.bytesize + log_tail.bytesize)

      expected = [build.author_name, 'Checkout', escaped_step_name, 'Upload', 'Deploy',
                  "#{escaped_log_output}#{log_tail}", 'has succeeded!']
      pattern = Regexp.new(expected.map { |text| Regexp.escape(text) }.join('.*'), Regexp::MULTILINE)
      expect { watch_until(streamed, 'success') }.to output(pattern).to_stdout
    end

    it 'retries a timed-out build detail request on the next poll' do
      polled = pause_after_polls(2)
      expect(CircleCI::CLI::Response::Build).to receive(:get).ordered.and_raise(Net::ReadTimeout)
      expect(CircleCI::CLI::Response::Build).to receive(:get).ordered.and_return(updated_build)
      expect_output_response(0, "recovered output\n")
      expect(CircleCI::CLI::Response::Build).to receive(:get).ordered.and_return(updated_build)
      expect_output_response("recovered output\n".bytesize)

      expect { watch_until(polled, 'success') }.to output(a_string_including("recovered output\n")).to_stdout
      expect(watcher.poll_error).to be_nil
    end

    it 'preserves the fatal polling error if completion is detected at the same time' do
      error = Thor::Error.new('CircleCI API error (HTTP 401): Unauthorized')
      expect(CircleCI::CLI::Response::Build).to receive(:get).once.and_raise(error)
      allow(watcher).to receive(:notify_started)

      expect(watcher.start.join(5)).to be_a(Thread)

      expect { watcher.stop('success') }.to raise_error(Thor::Error) { |raised| expect(raised).to equal(error) }
    end

    it 'continues polling from the last byte received after a connection reset' do
      streamed = pause_after_polls(2)
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      expect_output_response(0, 'é', error: Errno::ECONNRESET)
      expect_output_response(2, " done\n")
      expect_output_response(8)

      expect { watch_until(streamed, 'success') }
        .to output(a_string_matching(/\A[^é]*é done\n[^é]*\z/m)).to_stdout
    end

    it 'retries a timed-out log request at the last consumed byte without duplicating output' do
      polled = pause_after_polls(3)
      allow(watcher).to receive(:puts)
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      first_chunk = "é first\n"
      final_chunk = "last output\n"
      expect_output_response(0, first_chunk.b)
      expect(http).to receive(:request).ordered do |request|
        expect(request.path).to eq(output_path)
        expect(request['Range']).to eq("bytes=#{first_chunk.bytesize}-")
        raise Net::ReadTimeout
      end
      expect_output_response(first_chunk.bytesize, final_chunk.b)
      expect_output_response(first_chunk.bytesize + final_chunk.bytesize)

      expect { watch_until(polled, 'success') }.to output(first_chunk + final_chunk).to_stdout
    end

    context 'when actions in the same step finish on different refreshes' do
      let(:poll_count) { 6 }

      def multi_action_build(first_status, second_status)
        step = step_hash.call(name: 'Test', type: 'test', status: first_status, index: 1, step: 2)
        second = step_hash.call(name: 'Test', type: 'test', status: second_status, index: 2, step: 2)
        step['actions'].concat(second['actions'])
        build_response.call([step])
      end

      it 'reads an already completed action when it first observes the running step' do
        polled = pause_after_polls(1)
        allow(watcher).to receive(:puts)
        allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(multi_action_build('success', 'running'))

        expect_output_response(0, "completed output\n")
        expect_output_response(0, "live output\n", path: output_path.sub(%r{/1/2$}, '/2/2'))

        expect_output_response("live output\n".bytesize, path: output_path.sub(%r{/1/2$}, '/2/2'))

        expect { watch_until(polled, 'success') }.to output("completed output\nlive output\n").to_stdout
      end

      context 'with default output' do
        let(:watcher) { described_class.new(build) }

        it 'buffers already completed and live action logs until the step fails' do
          polled = pause_after_polls(1)
          allow(watcher).to receive(:puts)
          allow(CircleCI::CLI::Response::Build).to receive(:get)
            .and_return(multi_action_build('success', 'running'), multi_action_build('success', 'failed'))

          second_path = output_path.sub(%r{/1/2$}, '/2/2')
          live_output = "live output\n"
          expect_output_response(0, "completed output\n")
          expect_output_response(0, live_output, path: second_path)
          expect_output_response(live_output.bytesize, "final output\n", path: second_path)

          expect { watch_until(polled, 'failed') }.to output("completed output\nlive output\nfinal output\n").to_stdout
        end
      end

      it 'streams each action from byte zero and reads each final chunk exactly once' do
        polled = pause_after_polls(poll_count)
        allow(watcher).to receive(:puts)
        allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(
          multi_action_build('running', 'running'),
          multi_action_build('success', 'running'),
          multi_action_build('success', 'success')
        )

        second_path = output_path.sub(%r{/1/2$}, '/2/2')
        expect_output_response(0, "first\n\r")
        expect_output_response(0, "second\n", path: second_path)
        4.times do
          expect_output_response(7)
          expect_output_response(7, path: second_path)
        end
        expect_output_response(7, "\nfirst tail\n")
        expect_output_response(7, "second live\n", path: second_path)
        expect_output_response(19, "second tail\n", path: second_path)

        expect do
          watch_until(polled, 'success')
        end.to output("first\nsecond\n\nfirst tail\nsecond live\nsecond tail\n").to_stdout
      end
    end

    it 'fetches build details immediately and every five polling iterations' do
      refreshes = []
      polls = 0
      polled = pause_after_polls(11) { |count| polls = count }
      allow(CircleCI::CLI::Response::Build).to receive(:get).with('user', 'repo', 1234) do
        refreshes << polls
        build
      end

      expect { watch_until(polled, 'success') }.to output(a_string_including('Start watching')).to_stdout
      expect(refreshes).to eq([0, 5, 10, 11])
      expect(watcher.latest_detail).to equal(build)
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

  describe '#stop' do
    let(:initial_steps) { [step_hash.call(name: 'Build', type: 'build', status: 'running')] }
    let(:watcher) { described_class.new(build) }
    let(:output_path) { '/api/private/output/raw/github/user/repo/1234/output/0/0' }
    let(:failed_build) { build_response.call([step_hash.call(name: 'Build', type: 'build', status: 'failed')]) }

    it 'finishes an in-flight poll and refreshes before reporting completion' do
      stop_requested = watcher.instance_variable_get(:@stop_requested)
      stopping = Queue.new
      refreshing = Queue.new
      resume_refresh = Queue.new
      output = []
      refresh_threads = []

      allow(stop_requested).to receive(:pop).with(timeout: 1).and_return(nil)
      allow(stop_requested).to receive(:close).and_wrap_original do |close|
        close.call
        stopping << true
      end
      allow(watcher).to receive(:puts) { |line| output << line }
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      allow($stdout).to receive(:write) do |chunk|
        output << chunk.dup
        chunk.bytesize
      end
      expect_output_response(0, "buffered output\n")
      5.times { expect_output_response(16) }
      allow(CircleCI::CLI::Response::Build).to receive(:get) do
        refresh_threads << Thread.current
        next build if refresh_threads.one?

        refreshing << true
        resume_refresh.pop
        failed_build
      end

      worker = watcher.start
      Timeout.timeout(5) { refreshing.pop }
      stopper = Thread.new { watcher.stop('failed') }
      Timeout.timeout(5) { stopping.pop }
      resume_refresh << true
      Timeout.timeout(5) { refreshing.pop }
      expect(output.grep(/has failed/)).to be_empty
      resume_refresh << true
      expect(stopper.join(5)).to eq(stopper)

      expect(refresh_threads).to eq([worker, worker, worker])
      expect(output.drop(1)).to eq(
        [
          "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_red('Build')}",
          "buffered output\n",
          CircleCI::CLI::Printer.colorize_red('😥 user/repo #1234 has failed...')
        ]
      )
    ensure
      [worker, stopper].compact.each { |thread| thread.kill.join }
    end
  end

  context 'when an action publishes a final chunk between polls' do
    let(:initial_steps) { [step_hash.call(name: step_name, type: 'test', status: 'running', index: 1, step: 2)] }
    let(:finished_build) do
      build_response.call([step_hash.call(name: step_name, type: 'test', status: status, index: 1, step: 2)])
    end

    let(:polled) { pause_after_polls(poll_count) }

    before do
      polled
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(build, finished_build)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      expect_output_response(0, "first output\n")
      allow(watcher).to receive(:notify_started)
    end

    context 'with verbose output' do
      let(:watcher) { described_class.new(build, verbose: true) }
      let(:status) { 'success' }
      let(:poll_count) { 6 }

      it 'streams the final chunk on the regular refresh exactly once before completion' do
        response = Net::HTTPRangeNotSatisfiable.new('1.1', '416', 'Range Not Satisfiable')
        allow(response).to receive(:read_body).and_yield('No more bytes')
        expect(http).to receive(:request).ordered.exactly(4).times do |request, &read_response|
          expect(request['Range']).to eq('bytes=13-')
          read_response.call(response)
        end
        expect_output_response(13, 'final output')

        expect do
          watch_until(polled, status)
        end.to output(/\Afirst output\nfinal output\n(?!.*final output\n).*has succeeded!/m).to_stdout
      end
    end

    context 'with default output' do
      let(:watcher) { described_class.new(build) }
      let(:status) { 'failed' }
      let(:poll_count) { 1 }

      it 'includes the final chunk in the failed-step output when stopped' do
        expect_output_response(13, "final ".b + log_output.byteslice(0, 1), error: Errno::ECONNRESET)
        expect_output_response(20, log_output.byteslice(1..))
        replayed_output = Regexp.escape("first output\nfinal #{escaped_log_output}\n")

        expect do
          watch_until(polled, status)
        end.to output(/#{Regexp.escape(escaped_step_name)}.*#{replayed_output}.*has failed/m)
          .to_stdout.and output('').to_stderr
      end

      it 'reports incomplete output after the final retry fails and replays the bytes received' do
        expect_output_response(13, 'partial', error: EOFError)
        expect_output_response(20, ' tail', error: Net::ReadTimeout)

        expect do
          watch_until(polled, status)
        end.to output(a_string_including("first output\npartial tail\n", 'has failed')).to_stdout
           .and output("Warning: Step log output may be incomplete.\n").to_stderr
      end
    end
  end

  describe '#update_build' do
    let(:initial_steps) { [step_hash.call(name: 'Build', type: 'build', status: 'success')] }
    let(:watcher) { described_class.new(build, verbose: false) }
    let(:updated_build) { build_response.call([step_hash.call(name: 'Build', type: 'build', status: 'failed')]) }

    context 'with many unchanged steps' do
      let(:initial_steps) do
        Array.new(100) { |index| step_hash.call(name: "Step #{index}", type: 'test', status: 'success', step: index) }
      end
      let(:updated_build) { build_response.call(initial_steps) }

      it 'indexes previous step identities and materializes incoming steps once without printing transitions' do
        previous_steps = build.steps
        allow(build).to receive(:steps).and_return(previous_steps)
        allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
        previous_steps.each { |step| expect(step).to receive(:action_identity).once.and_call_original }
        expect(updated_build).to receive(:steps).once.and_call_original
        expect(watcher).not_to receive(:puts)

        watcher.send(:update_build)
      end
    end

    context 'with successive actions named Test' do
      let(:initial_steps) { [] }
      let(:first_running) { step_hash.call(name: 'Test', type: 'test', status: 'running', index: 1, step: 2) }
      let(:first_succeeded) { step_hash.call(name: 'Test', type: 'test', status: 'success', index: 1, step: 2) }
      let(:second_running) { step_hash.call(name: 'Test', type: 'test', status: 'running', index: 2, step: 2) }
      let(:second_failed) { step_hash.call(name: 'Test', type: 'test', status: 'failed', index: 2, step: 2) }

      it 'starts the new action at byte zero and replays only its output on failure' do
        first_build = build_response.call([first_running])
        second_build = build_response.call([first_succeeded, second_running])
        failed_build = build_response.call([first_succeeded, second_failed])
        allow(CircleCI::CLI::Response::Build).to receive(:get)
          .and_return(first_build, second_build, failed_build, failed_build)
        allow(watcher).to receive(:puts)
        allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)

        second_path = output_path.sub(%r{/1/2$}, '/2/2')
        expect_output_response(0, 'a' * 400)
        expect_output_response(400)
        expect_output_response(0, "second action output\n", path: second_path)
        expect_output_response(21, "second action tail\n", path: second_path)

        expect do
          2.times do
            watcher.send(:update_build)
            watcher.send(:update_actions)
          end
          2.times { watcher.send(:update_build) }
        end.to output("second action output\nsecond action tail\n").to_stdout

        expect(watcher).to have_received(:puts).with('Test').twice
        expect(watcher).to have_received(:puts).with(
          "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Test')}"
        ).once
        expect(watcher).to have_received(:puts).with(
          "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_red('Test')}"
        ).once
      ensure
        watcher.close
      end
    end

    it 'prints failed statuses and replays buffered output' do
      log_text = "captured output <%= \"log\" %>\n"
      watcher.send(:retain_output, build.steps.first.action_identity, log_text)
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      status = "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_red('Build')}"

      expect { watcher.send(:update_build) }.to output("#{status}\n#{log_text}").to_stdout
    end

    it 'prints new step statuses for success, failure, and in-progress steps' do
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(
        build_response.call(
          [
            step_hash.call(name: 'Build', type: 'build', status: 'success'),
            step_hash.call(name: step_name, type: 'test', status: 'failed', index: 1, step: 2),
            step_hash.call(name: 'Deploy', type: 'deploy', status: 'running', index: 2, step: 3)
          ]
        )
      )
      allow(watcher).to receive(:puts)

      watcher.instance_variable_set(:@steps, [])
      watcher.send(:update_build)

      expect(watcher).to have_received(:puts).with("\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Build')}")
      expect(watcher).to have_received(:puts).with("\e[2K\r#{CircleCI::CLI::Printer.colorize_red(escaped_step_name)}")
      expect(watcher).to have_received(:puts).with('Deploy')
    end

    it 'replaces a running step with a success status line' do
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(
        build_response.call([step_hash.call(name: step_name, type: 'build', status: 'success')])
      )
      allow(watcher).to receive(:puts)

      watcher.instance_variable_set(
        :@steps,
        [build_response.call([step_hash.call(name: step_name, type: 'build', status: 'running')]).steps.first]
      )
      watcher.send(:update_build)

      expect(watcher).to have_received(:puts).with(
        "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_green(escaped_step_name)}"
      )
    end
  end

  describe '#update_actions' do
    let(:initial_steps) { [] }
    let(:watcher) { described_class.new(build, verbose: false) }
    let(:updated_build) do
      build_response.call(
        [step_hash.call(name: step_name, type: 'test', status: 'running', index: 1, step: 2)]
      )
    end

    it 'buffers output and skips empty response bodies' do
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      allow(watcher).to receive(:puts)
      watcher.send(:update_build)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      expect_output_response(0, log_output)
      expect_output_response(log_output.bytesize)

      watcher.send(:update_actions)
      watcher.send(:update_actions)

      messages = watcher.instance_variable_get(:@messages)
      expect(messages.keys).to eq([[1, 2]])
      expect { messages.values.first.write_to($stdout) }.to output(escaped_log_output).to_stdout
    ensure
      watcher.close
    end
  end

  describe 'buffered step output' do
    let(:initial_steps) { [step_hash.call(name: 'Test', type: 'test', status: 'running')] }
    let(:watcher) { described_class.new(build) }
    let(:messages) { watcher.instance_variable_get(:@messages) }
    let(:output_path) { '/api/private/output/raw/github/user/repo/1234/output/0/0' }
    let(:first_chunk) { 'x' * (192 * 1024) }
    let(:second_chunk) { 'y' * (128 * 1024) }
    let(:last_chunk) { "last\n" }

    before do
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(build)
      allow(watcher).to receive(:puts)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      watcher.send(:update_build)
    end

    after { watcher.close }

    def collect_responses
      expect_output_response(0, first_chunk)
      expect_output_response(first_chunk.bytesize, second_chunk, last_chunk)
      watcher.send(:update_actions)
      expect(messages.values.first.instance_variable_get(:@file)).to be_nil
      watcher.send(:update_actions)
    end

    it 'replays split lines intact and terminates the final line after an empty response' do
      expect_output_response(0, 'hel')
      expect_output_response(3, "lo\r")
      expect_output_response(6, "\nlast line")
      3.times { watcher.send(:update_actions) }
      finish_step('failed', final_offset: 16)

      expect { watcher.send(:update_build) }.to output("hello\nlast line\n").to_stdout
    end

    it 'streams a single large response to disk and replays it once after failure' do
      expect_output_response(0, first_chunk, second_chunk, last_chunk)
      watcher.send(:update_actions)
      path = messages.values.first.instance_variable_get(:@file).path
      expect(messages.values.first.instance_variable_get(:@memory)).to be_nil
      finish_step('failed', final_offset: first_chunk.bytesize + second_chunk.bytesize + last_chunk.bytesize)

      expect do
        watcher.send(:update_build)
        watcher.send(:update_build)
      end.to output("#{first_chunk}#{second_chunk}#{last_chunk}").to_stdout
      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    it 'replays all collected chunks once after failure and removes the spill file' do
      collect_responses
      path = messages.values.first.instance_variable_get(:@file).path
      expect(messages.values.first.instance_variable_get(:@memory)).to be_nil
      finish_step('failed', final_offset: first_chunk.bytesize + second_chunk.bytesize + last_chunk.bytesize)

      expect do
        watcher.send(:update_build)
        watcher.send(:update_build)
      end.to output("#{first_chunk}#{second_chunk}#{last_chunk}").to_stdout
      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    it 'discards output and removes the spill file after success' do
      collect_responses
      path = messages.values.first.instance_variable_get(:@file).path
      finish_step('success', final_offset: first_chunk.bytesize + second_chunk.bytesize + last_chunk.bytesize)

      expect { watcher.send(:update_build) }.not_to output.to_stdout
      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    it 'removes an active step spill file when closed' do
      collect_responses
      path = messages.values.first.instance_variable_get(:@file).path

      watcher.close

      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    context 'when a live step exceeds the retention limit' do
      let(:limit) { first_chunk.bytesize + 96 * 1024 }

      before do
        stub_const('CircleCI::CLI::Command::StepLog::RETENTION_LIMIT', limit)
        expect_output_response(0, first_chunk, second_chunk, last_chunk)
        watcher.send(:update_actions)
        expect(File.size(spill_path)).to eq(limit)
      end

      def spill_path
        messages.values.first.instance_variable_get(:@file).path
      end

      it 'keeps polling from the full byte offset and reports truncation on failure' do
        path = spill_path
        finish_step('failed', final_offset: first_chunk.bytesize + second_chunk.bytesize + last_chunk.bytesize)
        retained = first_chunk + second_chunk.byteslice(0, limit - first_chunk.bytesize)

        expect { watcher.stop('failed') }
          .to output("#{retained}\n[Step log truncated: retention limit reached.]\n").to_stdout
        expect(File.exist?(path)).to be(false)
      end

      it 'removes the capped spill file when closed while the step is still running' do
        path = spill_path
        watcher.close

        expect(messages).to be_empty
        expect(File.exist?(path)).to be(false)
      end

      it 'shares the retention budget with other running steps' do
        other_step = step_hash.call(name: 'Other', type: 'test', status: 'running', step: 1)
        reordered_build = build_response.call([other_step, *initial_steps])
        allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(reordered_build)
        expect_output_response(first_chunk.bytesize + second_chunk.bytesize + last_chunk.bytesize)
        expect_output_response(0, second_chunk, first_chunk, path: output_path.sub(%r{/0$}, '/1'))
        path = spill_path

        watcher.send(:update_build)
        watcher.send(:update_actions)

        expect(messages.fetch([0, 1]).bytesize).to eq(0)
        expect(File.size(path)).to eq(limit)
      end
    end

    it 'stops polling and removes the spill file while the response body is blocked' do
      reading = Queue.new
      release = Queue.new
      response = Net::HTTPPartialContent.new('1.1', '206', 'Partial Content')
      allow(http).to receive(:request).and_yield(response)
      allow(response).to receive(:read_body) do |&read_chunk|
        read_chunk.call(first_chunk)
        read_chunk.call(second_chunk)
        reading << messages.values.first.instance_variable_get(:@file).path
        release.pop
      end

      watcher.start
      poller = watcher.instance_variable_get(:@build_thread)
      path = Timeout.timeout(5) { reading.pop }
      expect(File.exist?(path)).to be(true)

      Timeout.timeout(5) { watcher.close }

      expect(poller).not_to be_alive
      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    ensure
      release << true
    end

    it 'removes the spill file if the final build refresh fails' do
      collect_responses
      path = messages.values.first.instance_variable_get(:@file).path
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_raise(IOError)

      expect { watcher.stop('failed') }.to raise_error(IOError)
      expect(messages).to be_empty
      expect(File.exist?(path)).to be(false)
    end

    context 'when a successful step shares the running step name' do
      let(:successful_step) { step_hash.call(name: 'Test', type: 'test', status: 'success', step: 1) }
      let(:initial_steps) { super() + [successful_step] }

      it 'only reports the failed step and replays its buffered output once' do
        expect_output_response(0, last_chunk)
        watcher.send(:update_actions)
        finish_step('failed', final_offset: last_chunk.bytesize, other_steps: [successful_step])

        expect do
          watcher.send(:update_build)
          watcher.send(:update_build)
        end.to output(last_chunk).to_stdout
        expect(watcher).to have_received(:puts).once.with(
          "\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_red('Test')}"
        )
        expect(watcher).to have_received(:puts).once
        expect(messages).to be_empty
      end
    end

    def finish_step(status, final_offset:, other_steps: [])
      expect_output_response(final_offset)
      finished_step = step_hash.call(name: 'Test', type: 'test', status: status)
      finished = build_response.call([finished_step, *other_steps])
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(finished)
    end
  end
end
