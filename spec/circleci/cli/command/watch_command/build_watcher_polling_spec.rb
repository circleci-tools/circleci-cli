# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

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

  def expect_output_response(offset, *chunks, error: nil)
    expect(http).to receive(:request).ordered do |request, &read_response|
      expect(request).to be_a(Net::HTTP::Get)
      expect(request.path).to eq(output_path)
      expect(request['Range']).to eq("bytes=#{offset}-")
      response = Net::HTTPPartialContent.new('1.1', '206', 'Partial Content')
      allow(response).to receive(:read_body) do |&read_chunk|
        chunks.each(&read_chunk)
        raise error if error
      end
      read_response.call(response)
    end
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
      allow(Thread).to receive(:new) do |&block|
        block.call
        thread
      rescue Interrupt
        thread
      end
    end

    it 'prints new steps in API order and streams output from the first running step' do
      polls = 0
      allow(watcher).to receive(:sleep).with(1) do
        polls += 1
        raise Interrupt if polls == 2
      end
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      log_tail = " done <%= \"log\" %>\n"
      expect_output_response(0, log_output.byteslice(0, 1), log_output.byteslice(1, 9), log_output.byteslice(10..))
      expect_output_response(log_output.bytesize, log_tail)

      expected = ['Checkout', escaped_step_name, 'Upload', 'Deploy', "#{escaped_log_output}#{log_tail}", build.author_name]
      pattern = Regexp.new(expected.map { |text| Regexp.escape(text) }.join('.*'), Regexp::MULTILINE)
      expect { watcher.start }.to output(pattern).to_stdout
    end

    it 'continues polling from the last byte received after a connection reset' do
      polls = 0
      allow(watcher).to receive(:sleep).with(1) do
        polls += 1
        raise Interrupt if polls == 2
      end
      allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      expect_output_response(0, 'é', error: Errno::ECONNRESET)
      expect_output_response(2, " done\n")

      expect { watcher.start }.to output(a_string_matching(/\A[^é]*é done\n[^é]*\z/)).to_stdout
    end

    it 'fetches build details immediately and every five polling iterations' do
      polls = 0
      refreshes = []
      allow(watcher).to receive(:sleep).with(1) do
        polls += 1
        raise Interrupt if polls == 11
      end
      allow(CircleCI::CLI::Response::Build).to receive(:get).with('user', 'repo', 1234) do
        refreshes << polls
        build
      end

      expect { watcher.start }.to output(a_string_including('Start watching')).to_stdout
      expect(refreshes).to eq([0, 5, 10])
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
    let(:initial_steps) { [step_hash.call(name: step_name, type: 'test', status: 'running', index: 1, step: 2)] }
    let(:finished_build) do
      build_response.call([step_hash.call(name: step_name, type: 'test', status: status, index: 1, step: 2)])
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
        expect_output_response(13, "final output\n")

        expect do
          watcher.start
          watcher.stop(status)
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
          watcher.start
          watcher.stop(status)
        end.to output(/#{Regexp.escape(escaped_step_name)}.*#{replayed_output}.*has failed/m)
          .to_stdout.and output('').to_stderr
      end

      it 'reports incomplete output after the final retry fails and replays the bytes received' do
        expect_output_response(13, 'partial', error: EOFError)
        expect_output_response(20, ' tail', error: Net::ReadTimeout)

        expect do
          watcher.start
          watcher.stop(status)
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
        Array.new(100) { |index| step_hash.call(name: "Step #{index}", type: 'test', status: 'success') }
      end
      let(:updated_build) { build_response.call(initial_steps) }

      it 'indexes previous step identities and materializes incoming steps once without printing transitions' do
        previous_steps = build.steps
        allow(build).to receive(:steps).and_return(previous_steps)
        allow(CircleCI::CLI::Response::Build).to receive(:get).and_return(updated_build)
        previous_steps.each { |step| expect(step).to receive(:name).once.and_call_original }
        expect(updated_build).to receive(:steps).once.and_call_original
        expect(watcher).not_to receive(:puts)

        watcher.send(:update_build)
      end
    end

    it 'prints failed statuses and replays buffered output' do
      log_text = "captured output <%= \"log\" %>\n"
      log = CircleCI::CLI::Command::StepLog.new
      log.append(log_text)
      watcher.instance_variable_get(:@messages)[[0, 0, 'Build']] = log
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
    let(:current_step) do
      build_response.call(
        [step_hash.call(name: step_name, type: 'test', status: 'running', index: 1, step: 2)]
      ).steps.first
    end

    it 'buffers output and skips empty response bodies' do
      watcher.instance_variable_set(:@current_step, current_step)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      expect_output_response(0, log_output)
      expect_output_response(log_output.bytesize)

      watcher.send(:update_actions)
      watcher.send(:update_actions)

      messages = watcher.instance_variable_get(:@messages)
      expect(messages.keys).to eq([[1, 2, step_name]])
      expect { messages.values.first.write_to($stdout) }.to output("#{escaped_log_output}\n").to_stdout
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
      end.to output("#{first_chunk}\n#{second_chunk}#{last_chunk}").to_stdout
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
