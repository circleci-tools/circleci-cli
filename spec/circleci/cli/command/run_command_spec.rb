# frozen_string_literal: true

require 'socket'
require 'spec_helper'
require 'timeout'

describe CircleCI::CLI::Runner, 'run' do
  let(:client) { CircleCI::CLI::Networking::HTTPClient }
  let(:session) { instance_double(client::Session, close: nil) }
  let(:fixtures) { JSON.parse(File.read(File.expand_path('../../../fixtures/run_responses.json', __dir__))) }
  let(:run_id) { fixtures.fetch('run').fetch('data').fetch('id') }
  let(:headers) { { 'Authorization' => 'Bearer test-token' } }
  let(:workflows_path) { "workflows?filter%5Brun_id%5D=#{run_id}" }

  before do
    allow(client::Session).to receive(:new).with(max_retries: 1).and_return(session)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CIRCLE_CI_TOKEN', nil).and_return('test-token')
  end

  def stub_get(path, body, response_class: Net::HTTPOK, code: '200')
    response = response_class.new('1.1', code, '')
    allow(response).to receive(:body).and_return(JSON.generate(body))
    allow(session).to receive(:get_raw).with("https://circleci.com/api/v3/#{path}", headers).and_return(response)
  end

  it 'shows jobs grouped by workflow across pages, including approvals without a job number' do
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, fixtures.fetch('workflows_first_page'))
    stub_get("#{workflows_path}&page%5Bcursor%5D=cursor%2B%2F%3D", fixtures.fetch('workflows_last_page'))
    { 'checks' => 'first', 'deploy' => 'last' }.each do |name, page|
      workflow = fixtures.fetch("workflows_#{page}_page").fetch('data').first
      stub_get("jobs?filter%5Bworkflow_id%5D=#{workflow.fetch('id')}", fixtures.fetch("#{name}_jobs"))
    end

    expected = <<~TABLE
      +------------------------------------------------------+
      |                  Run #123 (started)                  |
      +----------+---------+--------------------+------------+
      | Workflow | Job     | Status             | Job Number |
      +----------+---------+--------------------+------------+
      | checks   | test    | failed             | 42         |
      | checks   | lint    | running            | 43         |
      | deploy   | approve | waiting (approval) | -          |
      +----------+---------+--------------------+------------+
    TABLE

    expect { described_class.start(['run', run_id]) }.to output(expected).to_stdout
  end

  it 'escapes terminal controls in the title and job rows' do
    run = fixtures.fetch('run')
    run.fetch('data').fetch('attributes').merge!('number' => "123\r", 'phase' => "started\t")
    workflows = fixtures.fetch('workflows_first_page')
    workflows.fetch('page')['next'] = nil
    workflow = workflows.fetch('data').first
    workflow.fetch('attributes')['name'] = "checks\r"
    jobs = fixtures.fetch('checks_jobs')
    jobs.fetch('data').first.fetch('attributes').merge!(
      'name' => "test\e", 'outcome' => "failed\n", 'number' => "42\b"
    )
    stub_get("runs/#{run_id}", run)
    stub_get(workflows_path, workflows)
    stub_get("jobs?filter%5Bworkflow_id%5D=#{workflow.fetch('id')}", jobs)

    expected = <<~'TABLE'
      +-------------------------------------------------+
      |           Run #123\x0D (started\x09)            |
      +------------+----------+------------+------------+
      | Workflow   | Job      | Status     | Job Number |
      +------------+----------+------------+------------+
      | checks\x0D | test\x1B | failed\x0A | 42\x08     |
      | checks\x0D | lint     | running    | 43         |
      +------------+----------+------------+------------+
    TABLE

    expect { described_class.start(['run', run_id]) }.to output(expected).to_stdout
  end

  it 'reports an empty run' do
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, { 'data' => [], 'page' => { 'next' => nil } })

    expect { described_class.start(['run', run_id]) }.to output(/No workflows found/).to_stdout
  end

  it 'gives up and reports an error when the workflows cursor never terminates' do
    max_pages = CircleCI::CLI::Command::RunLookup::MAX_WORKFLOW_PAGES
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, { 'data' => [], 'page' => { 'next' => 'same-cursor' } })
    stub_get("#{workflows_path}&page%5Bcursor%5D=same-cursor", { 'data' => [], 'page' => { 'next' => 'same-cursor' } })

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("Too many workflow pages.\n").to_stderr
    expect(session).to have_received(:get_raw).with("https://circleci.com/api/v3/#{workflows_path}", headers).once
    expect(session).to have_received(:get_raw)
      .with("https://circleci.com/api/v3/#{workflows_path}&page%5Bcursor%5D=same-cursor", headers)
      .exactly(max_pages - 1).times
  end

  context 'with --failed-tests' do
    let(:args) { ['run', run_id, '--failed-tests'] }
    let(:unit_id) { '123e4567-e89b-12d3-a456-426614174010' }
    let(:integration_id) { '123e4567-e89b-12d3-a456-426614174011' }
    let(:system_id) { '123e4567-e89b-12d3-a456-426614174012' }
    let(:smoke_id) { '123e4567-e89b-12d3-a456-426614174013' }

    before do
      stub_get("runs/#{run_id}", fixtures.fetch('run'))
    end

    def stub_workflow_page(page, jobs, cursor: '')
      response = fixtures.fetch("workflows_#{page}_page")
      stub_get("#{workflows_path}#{cursor}", response)
      workflow_id = response.fetch('data').first.fetch('id')
      stub_get("jobs?filter%5Bworkflow_id%5D=#{workflow_id}", { 'data' => jobs })
    end

    def failed_job(id, name)
      { 'id' => id, 'attributes' => { 'name' => name, 'outcome' => 'failed' } }
    end

    def stub_test_response(id, response)
      allow(session).to receive(:get_raw).with("https://circleci.com/api/v3/jobs/#{id}/tests", headers)
                                        .and_yield(response).and_return(response)
    end

    def stub_test_chunks(id, chunks, response: Net::HTTPOK.new('1.1', '200', ''))
      expect(response).not_to receive(:body)
      allow(response).to receive(:read_body) { |&read_chunk| chunks.each(&read_chunk) }
      stub_test_response(id, response)
    end

    it 'groups failures across workflow pages and distinguishes empty and passing results' do
      lint = fixtures.fetch('checks_jobs').fetch('data').last
      stub_workflow_page('first', [failed_job(unit_id, 'unit'), failed_job(integration_id, 'integration'), lint])
      deploy_jobs = [failed_job(system_id, 'system'), failed_job(smoke_id, 'smoke')]
      stub_workflow_page('last', deploy_jobs, cursor: '&page%5Bcursor%5D=cursor%2B%2F%3D')
      failure = { 'name' => 'rejects an expired token', 'result' => 'failure',
                  'file' => 'spec/token_spec.rb', 'message' => "Expected rejection\nReceived \e success" }
      fileless_failure = { 'name' => 'rejects the café token', 'result' => 'failure', 'message' => 'Expected an error' }
      passing = { 'name' => 'accepts an active token', 'result' => 'success' }
      records = [failure, passing, failure].map { |record| JSON.generate(record) }.join("\r\n")
      stub_test_chunks(unit_id, [records[0, 10], records[10..]])
      stub_test_chunks(integration_id, [], response: Net::HTTPNoContent.new('1.1', '204', ''))
      stub_test_chunks(system_id, JSON.generate(fileless_failure).each_byte.lazy.map(&:chr))
      stub_test_chunks(smoke_id, [" \r\n\t", "\n#{JSON.generate(passing)}\n"])

      expected = <<~'SUMMARY'
        Failed tests

        checks
          unit
            - rejects an expired token (spec/token_spec.rb)
              Expected rejection
              Received \x1B success
            - rejects an expired token (spec/token_spec.rb)
              Expected rejection
              Received \x1B success
          integration
            No uploaded test results.

        deploy
          system
            - rejects the café token
              Expected an error
          smoke
            No failures in uploaded test results.
      SUMMARY
      expect { described_class.start(args) }.to output(/#{Regexp.escape(expected)}\z/).to_stdout
      expect(session).to have_received(:get_raw).with(%r{/jobs\?filter%5Bworkflow_id%5D=}, headers).twice
    end

    it 'formats only failures from a large streamed result set' do
      fixtures.fetch('workflows_first_page').fetch('page')['next'] = nil
      stub_workflow_page('first', [failed_job(unit_id, 'unit')])
      passing_chunk = "{\"result\":\"success\"}\n" * 100
      failure = { 'name' => 'fails after passing tests', 'result' => 'failure' }
      chunks = Enumerator.new do |stream|
        1000.times { stream << passing_chunk }
        stream << JSON.generate(failure)
      end
      stub_test_chunks(unit_id, chunks)
      printer = CircleCI::CLI::Printer::FailedTestsPrinter
      expect(printer).to receive(:format_failure).with(failure).once.and_call_original

      expect { described_class.start(args) }.to output(/  unit\n    - fails after passing tests\n\z/).to_stdout
    end

    it 'stops reading the response once the output budget is full and closes the connection' do
      command = CircleCI::CLI::Command::RunCommand.new('test-token')
      summary = CircleCI::CLI::Command::FailedTestsSummary
      fixtures.fetch('workflows_first_page').fetch('page')['next'] = nil
      stub_workflow_page('first', [failed_job(unit_id, 'unit')])
      # Each message stays under TestResultLines::MAX_RECORD_BYTES so every record is parsed;
      # the fillers exist only to push the cumulative output past MAX_OUTPUT_BYTES at "kept".
      kept_message = 'a' * 250_000
      dropped_message = 'b' * 250_000
      filler_message = 'f' * 250_000
      fillers = Array.new(3) { |i| JSON.generate('name' => "filler#{i}", 'result' => 'failure', 'message' => filler_message) }
      kept = JSON.generate('name' => 'kept', 'result' => 'failure', 'message' => kept_message)
      dropped = JSON.generate('name' => 'dropped', 'result' => 'failure', 'message' => dropped_message)
      chunks = Enumerator.new do |stream|
        stream << "#{(fillers + [kept, dropped]).join("\n")}\n"
        raise 'test results should not be read past the output budget'
      end
      stub_test_chunks(unit_id, chunks)

      report = command.summary(run_id, failed_tests: true)

      expect(report).to end_with("- kept\n      #{kept_message}#{summary::TRUNCATION_NOTICE}")
      expect(report).not_to include('dropped')
      # One extra close beyond the baseline 3 (title/workflows, workflow jobs, test session) for the
      # abandoned connection, on top of the worker's own close once its queue is drained.
      expect(session).to have_received(:close).exactly(4).times
    end

    it 'reads the full response when the report stays within the output budget' do
      fixtures.fetch('workflows_first_page').fetch('page')['next'] = nil
      stub_workflow_page('first', [failed_job(unit_id, 'unit')])
      first = JSON.generate('name' => 'first', 'result' => 'failure')
      last = JSON.generate('name' => 'last', 'result' => 'failure')
      chunks = Enumerator.new do |stream|
        stream << "#{first}\n"
        stream << "#{last}\n"
      end
      stub_test_chunks(unit_id, chunks)

      expect { described_class.start(args) }.to output(/  unit\n    - first\n    - last\n\z/).to_stdout
      expect(session).to have_received(:close).exactly(3).times
    end

    context 'with a failed request in the same batch as uploaded failures' do
      let(:summary) { CircleCI::CLI::Command::FailedTestsSummary }
      let(:retained) { "Failed tests\n\nchecks\n  unit\n    - first\n    - second" }

      before do
        fixtures.fetch('workflows_first_page').fetch('page')['next'] = nil
        stub_workflow_page('first', [failed_job(unit_id, 'unit'), failed_job(integration_id, 'integration')])
        stub_test_chunks(unit_id, %w[first second].map { |name| "#{JSON.generate(name:, result: 'failure')}\n" })
        stub_test_chunks(integration_id, ["invalid JSON\n"])
      end

      it 'prints the workflow table and retained failures when the budget is filled exactly' do
        stub_const("#{summary}::MAX_OUTPUT_BYTES", retained.bytesize + summary::TRUNCATION_NOTICE.bytesize)
        table = /\| checks +\| unit +\| failed .*\n\| checks +\| integration +\| failed /
        ending = Regexp.escape("#{retained}#{summary::TRUNCATION_NOTICE}\n")

        expect { described_class.start(args) }.to output(/#{table}.*#{ending}\z/m).to_stdout
      end

      it 'truncates a capped result before surfacing the next job error' do
        limit = retained.bytesize + summary::TRUNCATION_NOTICE.bytesize + 1
        stub_const("#{summary}::MAX_OUTPUT_BYTES", limit)
        records = ['first', 'second', 'x' * limit].map { |name| "#{JSON.generate(name:, result: 'failure')}\n" }
        stub_test_chunks(unit_id, records)

        ending = Regexp.escape("#{retained}#{summary::TRUNCATION_NOTICE}\n")
        expect { described_class.start(args) }.to output(/#{ending}\z/).to_stdout
      end

      it 'reports the error with job context when output budget remains' do
        expect do
          expect { described_class.start(args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Unable to load test results for job integration (#{integration_id}): " \
                      "CircleCI API returned invalid JSON Lines.\n").to_stderr
      end
    end

    it 'skips oversized records split across chunks and resumes at the next record' do
      limit = CircleCI::CLI::Command::TestResultLines::MAX_RECORD_BYTES
      fixtures.fetch('workflows_first_page').fetch('page')['next'] = nil
      stub_workflow_page('first', [failed_job(unit_id, 'unit')])
      first = JSON.generate('name' => 'first', 'result' => 'failure')
      last = JSON.generate('name' => 'last', 'result' => 'failure')
      chunks = ["#{first}\n{\"result\":\"failure\",\"message\":\"", 'é' * (limit / 2),
                "\"}\n#{last}\n{\"message\":\"", 'x' * limit]
      stub_test_chunks(unit_id, chunks)

      expect { described_class.start(args) }.to output(
        /  unit\n    - first\n    - last\n\nFailed test output truncated\. Some uploaded test results were omitted\.\n\z/
      ).to_stdout
    end

    it 'bounds rendered failures across jobs without splitting a failure' do
      command = CircleCI::CLI::Command::RunCommand.new('test-token')
      summary = CircleCI::CLI::Command::FailedTestsSummary
      names = %w[unit integration system smoke browser acceptance]
      jobs = names.each_with_index.map { |name, index| failed_job(index + 1, name) }
      stub_workflow_page('first', jobs.take(4))
      stub_workflow_page('last', jobs.drop(4), cursor: '&page%5Bcursor%5D=cursor%2B%2F%3D')
      message = 'é' * 500
      jobs.each do |job|
        name = job.fetch('attributes').fetch('name')
        chunks = 200.times.lazy.map do |index|
          "#{JSON.generate('name' => "#{name}-#{index}", 'result' => 'failure', 'message' => message)}\n"
        end
        stub_test_chunks(job.fetch('id'), chunks)
      end

      report = command.summary(run_id, failed_tests: true).split("\n\nFailed tests", 2).last.prepend('Failed tests')
      expect(report.bytesize).to be <= summary::MAX_OUTPUT_BYTES
      expect(report).to end_with(summary::TRUNCATION_NOTICE)
      details = report.scan(/^    - (.+)\n      (.*)$/)
      expected_names = names.flat_map { |name| 200.times.map { |index| "#{name}-#{index}" } }
      expect(details.map(&:first)).to eq(expected_names.take(details.size))
      expect(details.size).to be_between(1001, 1199)
      expect(details.map(&:last).uniq).to eq([message])
      expect(report.scan(/^    - /).size).to eq(details.size)
    end

    it 'reports whitespace-only results as no uploaded tests' do
      fixtures.fetch('workflows_first_page').fetch('page')['next'] = nil
      stub_workflow_page('first', [failed_job(unit_id, 'unit')])
      stub_test_chunks(unit_id, [" \r", "\n\t"])

      expect { described_class.start(args) }.to output(/No uploaded test results\./).to_stdout
    end

    it 'bounds concurrent test requests and preserves order after retrying a partial response' do
      server = TCPServer.new('127.0.0.1', 0)
      sockets = []
      allow(client::Session).to receive(:new).with(max_retries: 1).and_call_original
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true) do
        Net::HTTP.new('127.0.0.1', server.addr[1], nil).start
      end
      workflows = %w[checks deploy].map { |name| { 'id' => name, 'attributes' => { 'name' => name } } }
      command = CircleCI::CLI::Command::RunCommand.new('test-token')
      summary = Thread.new { command.summary(run_id, failed_tests: true) }

      Timeout.timeout(5) do
        sockets << server.accept
        metadata = sockets.first
        expect(read_request(metadata)).to eq("runs/#{run_id}")
        write_response(metadata, fixtures.fetch('run'))
        expect(read_request(metadata)).to eq(workflows_path)
        write_response(metadata, { 'data' => workflows, 'page' => { 'next' => nil } })

        2.times do
          socket = server.accept
          sockets << socket
          workflow = read_request(socket).split('=').last
          ids = workflow == 'checks' ? (1..3) : (4..5)
          write_response(socket, { 'data' => ids.map { |id| failed_job(id, "job-#{id}") } })
        end

        4.times { sockets << server.accept }
        workers = sockets.last(4).to_h { |socket| [read_request(socket), socket] }
        expect(workers.keys).to match_array((1..4).map { |id| "jobs/#{id}/tests" })

        workers.to_a.reverse_each do |path, socket|
          id = path.split('/')[1]
          write_response(socket, { 'name' => "failure-#{id}", 'result' => 'failure' })
        end
        workers.each_value { |socket| expect(socket.read).to eq('') }

        sockets << server.accept
        interrupted_socket = sockets.last
        expect(read_request(interrupted_socket)).to eq('jobs/5/tests')
        interrupted = "{\"name\":\"interrupted failure\",\"result\":\"failure\"}\n{\"result\":"
        interrupted_socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{interrupted.bytesize + 1}\r\n\r\n#{interrupted}")
        interrupted_socket.close

        sockets << server.accept
        retried = sockets.last
        expect(read_request(retried)).to eq('jobs/5/tests')
        write_response(retried, { 'name' => 'failure-5', 'result' => 'failure' })
        expect(retried.read).to eq('')
        expect(IO.select([server], nil, nil, 0)).to be_nil

        report = summary.value.split("Failed tests\n\n").last
        expect(report.lines.map(&:strip)).to eq(
          ['checks', 'job-1', '- failure-1', 'job-2', '- failure-2', 'job-3', '- failure-3',
           '', 'deploy', 'job-4', '- failure-4', 'job-5', '- failure-5']
        )
      end
    ensure
      sockets&.each(&:close)
      server&.close
      summary&.kill&.join
    end

    it 'reports when no jobs failed' do
      stub_get(workflows_path, { 'data' => [], 'page' => { 'next' => nil } })

      expect { described_class.start(args) }.to output(/No failed jobs found\./).to_stdout
    end

    context 'when results cannot be loaded' do
      before do
        fixtures.fetch('workflows_first_page').fetch('page')['next'] = nil
        stub_workflow_page('first', [failed_job(unit_id, 'unit')])
      end

      it 'reports the failed request and job on stderr and exits unsuccessfully' do
        response = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
        allow(response).to receive(:body).and_return('{"error":{"detail":"Access denied"}}')
        expect(response).not_to receive(:read_body)
        stub_test_response(unit_id, response)

        expect do
          expect { described_class.start(args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Unable to load test results for job unit (#{unit_id}): " \
                      "CircleCI API error (HTTP 403): Access denied\n").to_stderr
      end

      { 'a non-object' => "[]\n", 'invalid JSON' => '{"result":' }.each do |description, line|
        it "reports #{description} in a JSON Lines response" do
          stub_test_chunks(unit_id, ["{\"result\":\"failure\"}\n", line])

          expect do
            expect { described_class.start(args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          end.to output("Unable to load test results for job unit (#{unit_id}): " \
                        "CircleCI API returned invalid JSON Lines.\n").to_stderr
        end
      end

      it 'reports a timeout while reading the response body' do
        url = "https://circleci.com/api/v3/jobs/#{unit_id}/tests"
        timeout = Net::ReadTimeout.new('test results timed out')
        chunks = Enumerator.new do |stream|
          stream << "{\"result\":\"success\"}\n"
          raise timeout
        end
        stub_test_chunks(unit_id, chunks)

        expect do
          expect { described_class.start(args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Unable to load test results for job unit (#{unit_id}): " \
                      "CircleCI API request failed (GET #{url}): #{timeout.message}\n").to_stderr
        expect(session).to have_received(:get_raw).with(url, headers).twice
      end
    end
  end

  it 'overlaps jobs requests up to four at a time and renders workflows in API order' do
    workflows = (1..8).map { |id| { 'id' => id, 'attributes' => { 'name' => "workflow-#{id}" } } }
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, { 'data' => workflows, 'page' => { 'next' => nil } })

    started = Queue.new
    finished = Queue.new
    first_request = Queue.new
    other_requests = Queue.new
    mutex = Mutex.new
    active = peak = 0
    response = Net::HTTPOK.new('1.1', '200', '')
    allow(response).to receive(:body).and_return(JSON.generate(fixtures.fetch('checks_jobs')))
    allow(session).to receive(:get_raw).with(%r{/jobs\?filter%5Bworkflow_id%5D=\d+\z}, headers) do |url, _headers|
      mutex.synchronize do
        active += 1
        peak = [peak, active].max
      end
      started << url
      (url.end_with?('=1') ? first_request : other_requests).pop
      mutex.synchronize { active -= 1 }
      finished << url
      response
    end

    command = CircleCI::CLI::Command::RunCommand.new('test-token')
    summary = Thread.new { command.summary(run_id) }
    Timeout.timeout(5) do
      4.times { started.pop }
      7.times { other_requests << true }
      7.times { finished.pop }
    end
    first_request << true

    expect(summary.value.scan(/(workflow-\d+)\s+\| (test|lint)/)).to eq(
      (1..8).flat_map { |id| %w[test lint].map { |job| ["workflow-#{id}", job] } }
    )
    expect(peak).to eq(4)
  ensure
    first_request&.close
    other_requests&.close
    summary&.join
  end

  it 'reuses keep-alive connections for workflow pages and for jobs within a worker' do
    server = TCPServer.new('127.0.0.1', 0)
    sockets = []
    allow(client::Session).to receive(:new).with(max_retries: 1).and_call_original
    allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true) do
      Net::HTTP.new('127.0.0.1', server.addr[1], nil).start
    end
    workflows = (1..5).map { |id| { 'id' => id, 'attributes' => { 'name' => "workflow-#{id}" } } }
    command = CircleCI::CLI::Command::RunCommand.new('test-token')
    summary = Thread.new { command.summary(run_id) }

    Timeout.timeout(5) do
      sockets << server.accept
      metadata = sockets.first
      expect(read_request(metadata)).to eq("runs/#{run_id}")
      write_response(metadata, fixtures.fetch('run'))
      expect(read_request(metadata)).to eq(workflows_path)
      write_response(metadata, { 'data' => workflows.first(2), 'page' => { 'next' => 'more' } })
      expect(read_request(metadata)).to eq("#{workflows_path}&page%5Bcursor%5D=more")
      write_response(metadata, { 'data' => workflows.drop(2), 'page' => { 'next' => nil } })
      expect(metadata.read).to eq('')

      4.times { sockets << server.accept }
      workers = sockets.drop(1)
      expect(workers.map { |socket| read_request(socket) }).to match_array(
        (1..4).map { |id| "jobs?filter%5Bworkflow_id%5D=#{id}" }
      )
      jobs = { 'data' => [] }
      write_response(workers.first, jobs)
      expect(read_request(workers.first)).to eq('jobs?filter%5Bworkflow_id%5D=5')
      workers.each { |socket| write_response(socket, jobs) }
      workers.each { |socket| expect(socket.read).to eq('') }
      expect(summary.value.scan(/workflow-\d+/)).to eq((1..5).map { |id| "workflow-#{id}" })
    end
  ensure
    sockets&.each(&:close)
    server&.close
    summary&.kill&.join
  end

  def read_request(socket)
    request_line = socket.gets
    headers = socket.each_line.take_while { |line| line != "\r\n" }
    expect(headers).to include("Authorization: Bearer test-token\r\n")
    request_line.split.fetch(1).delete_prefix('/api/v3/')
  end

  def write_response(socket, payload)
    body = JSON.generate(payload)
    socket.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}")
  end

  it 'reports a jobs API failure on stderr and exits unsuccessfully' do
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    workflows = %w[first last].flat_map { |page| fixtures.fetch("workflows_#{page}_page").fetch('data') }
    stub_get(workflows_path, { 'data' => workflows, 'page' => { 'next' => nil } })
    first_workflow, last_workflow = workflows
    stub_get("jobs?filter%5Bworkflow_id%5D=#{first_workflow.fetch('id')}", fixtures.fetch('checks_jobs'))
    stub_get("jobs?filter%5Bworkflow_id%5D=#{last_workflow.fetch('id')}", { 'error' => { 'detail' => 'Jobs unavailable' } },
             response_class: Net::HTTPServiceUnavailable, code: '503')

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 503): Jobs unavailable\n").to_stderr
    expect(session).to have_received(:close).exactly(3).times
  end

  it 'stops queued job requests after a failure and waits for requests in flight' do
    workflows = (1..8).map { |id| { 'id' => id, 'attributes' => { 'name' => "workflow-#{id}" } } }
    stub_get("runs/#{run_id}", fixtures.fetch('run'))
    stub_get(workflows_path, { 'data' => workflows, 'page' => { 'next' => nil } })

    started = Queue.new
    failure_worker = Queue.new
    fail_request = Queue.new
    finish_requests = Queue.new
    success = Net::HTTPOK.new('1.1', '200', '')
    allow(success).to receive(:body).and_return(JSON.generate(fixtures.fetch('checks_jobs')))
    failure = Net::HTTPServiceUnavailable.new('1.1', '503', '')
    allow(failure).to receive(:body).and_return('{"error":{"detail":"Jobs unavailable"}}')
    jobs_url = %r{/jobs\?filter%5Bworkflow_id%5D=\d+\z}
    allow(session).to receive(:get_raw).with(jobs_url, headers) do |url, _headers|
      id = url.split('=').last.to_i
      started << id
      if id == 1
        failure_worker << Thread.current
        fail_request.pop
        failure
      else
        finish_requests.pop if id <= 4
        success
      end
    end

    command = CircleCI::CLI::Command::RunCommand.new('test-token')
    summary = Thread.new do
      command.summary(run_id)
    rescue Thor::Error => e
      e
    end
    Timeout.timeout(5) do
      expect(Array.new(4) { started.pop }).to match_array(1..4)
      fail_request << true
      failure_worker.pop.join
      expect(summary).to be_alive
      finish_requests.close
      expect(summary.value).to be_a(Thor::Error)
      expect(summary.value.message).to eq('CircleCI API error (HTTP 503): Jobs unavailable')
    end
    expect(session).to have_received(:get_raw).with(jobs_url, headers).exactly(4).times
  ensure
    fail_request&.close
    finish_requests&.close
    summary&.join
  end

  it 'rejects an invalid run ID without prompting for a token or requesting the API' do
    expect(CircleCI::CLI::Command::RunCommand).not_to receive(:setup_token)
    expect(client::Session).not_to receive(:new)

    expect do
      expect { described_class.start(%w[run 123]) }.to raise_error(SystemExit) { |error|
        expect(error.status).to eq(1)
      }
    end.to output("Run ID must be a UUID.\n").to_stderr
  end

  it 'reports API failures on stderr and exits unsuccessfully' do
    stub_get("runs/#{run_id}", { 'error' => { 'detail' => 'Run not found' } },
             response_class: Net::HTTPNotFound, code: '404')

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 404): Run not found\n").to_stderr
    expect(session).to have_received(:close).once
  end

  %w[detail title].each do |field|
    it "escapes control characters in the API error #{field} on stderr and exits unsuccessfully" do
      stub_get("runs/#{run_id}", { 'error' => { field => "Run not found\r\nCheck the ID" } },
               response_class: Net::HTTPNotFound, code: '404')

      expect do
        expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
          expect(error.status).not_to be_zero
        }
      end.to output("CircleCI API error (HTTP 404): Run not found\\x0D\\x0ACheck the ID\n").to_stderr
    end
  end

  it 'reports invalid JSON in a successful API response' do
    response = Net::HTTPOK.new('1.1', '200', '')
    allow(response).to receive(:body).and_return('<html>Invalid response</html>')
    allow(session).to receive(:get_raw).with("https://circleci.com/api/v3/runs/#{run_id}", headers).and_return(response)

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API returned invalid JSON.\n").to_stderr
  end

  it 'reports the HTTP status when an API failure has a string error' do
    stub_get("runs/#{run_id}", { 'error' => 'Bad gateway' },
             response_class: Net::HTTPBadGateway, code: '502')

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 502)\n").to_stderr
  end

  it 'reports the error title when the detail is empty' do
    stub_get("runs/#{run_id}", { 'error' => { 'detail' => '', 'title' => 'Bad gateway' } },
             response_class: Net::HTTPBadGateway, code: '502')

    expect do
      expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
        expect(error.status).not_to be_zero
      }
    end.to output("CircleCI API error (HTTP 502): Bad gateway\n").to_stderr
  end

  context 'when a request times out' do
    let(:run_path) { "runs/#{run_id}" }

    {
      Net::OpenTimeout => ['connection timed out', :run_path],
      Net::ReadTimeout => ['read timed out', :workflows_path]
    }.each do |exception, (message, path)|
      it "reports #{exception} on stderr and exits unsuccessfully" do
        stub_get(run_path, fixtures.fetch('run')) if path == :workflows_path
        url = "https://circleci.com/api/v3/#{public_send(path)}"
        timeout = exception.new(message)
        allow(session).to receive(:get_raw).with(url, headers).and_raise(timeout)

        expect do
          expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
            expect(error.status).not_to be_zero
          }
        end.to output("CircleCI API request failed (GET #{url}): #{timeout.message}\n").to_stderr
      end
    end
  end

  [nil, '<html>Bad gateway</html>'].each do |body|
    description = body.nil? ? 'no body' : 'an invalid JSON body'
    it "reports the HTTP status when an API failure has #{description}" do
      response = Net::HTTPBadGateway.new('1.1', '502', '')
      allow(response).to receive(:body).and_return(body)
      allow(session).to receive(:get_raw).with("https://circleci.com/api/v3/runs/#{run_id}", headers).and_return(response)

      expect do
        expect { described_class.start(['run', run_id]) }.to raise_error(SystemExit) { |error|
          expect(error.status).not_to be_zero
        }
      end.to output("CircleCI API error (HTTP 502)\n").to_stderr
    end
  end
end
