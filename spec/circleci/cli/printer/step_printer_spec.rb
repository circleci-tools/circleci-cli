# frozen_string_literal: true

require 'spec_helper'
require 'weakref'

describe CircleCI::CLI::Printer::StepPrinter, type: :printer do
  def successful_log_response(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body).and_yield(body)
    response
  end

  describe '#to_s' do
    subject { described_class.new(steps, pretty: pretty).to_s }

    let(:http) { instance_double(Net::HTTP) }

    before do
      allow(http).to receive(:max_retries=).with(0)
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).with(an_instance_of(Net::HTTP::Get).and(have_attributes(path: '/output/123')))
        .and_yield(successful_log_response('[{"message":"action log"}]'))
      allow(http).to receive(:request).with(have_attributes(path: '/output/456'))
        .and_yield(successful_log_response('[{"message":"successful action log"}]'))
    end

    after do
      expect(http).to have_received(:request).with(have_attributes(path: '/output/123')).once
      expect(http).not_to have_received(:request).with(have_attributes(path: '/output/456'))
    end

    let(:steps) do
      steps = [
        { 'name' => 'waiting', 'actions' => [] },
        {
          'actions' => [
            { 'type' => 'build', 'name' => 'Dependency', 'status' => 'ok', 'run_time_millis' => 61_999 },
            {
              'type' => 'build', 'name' => 'Checkout', 'status' => 'success', 'run_time_millis' => 1200,
              'output_url' => 'https://circleci.com/output/456'
            }
          ]
        },
        {
          'actions' => [
            {
              'type' => 'test', 'name' => 'Test', 'status' => 'timedout', 'run_time_millis' => 1_200,
              'output_url' => 'https://circleci.com/output/123'
            }
          ]
        },
        {
          'actions' => [
            { 'type' => 'build', 'name' => 'Build', 'status' => 'canceled', 'run_time_millis' => 25_000 }
          ]
        },
        {
          'actions' => [
            { 'type' => 'deploy', 'name' => 'Deploy', 'status' => 'no_tests' }
          ]
        }
      ]
      CircleCI::CLI::Response::Build.new('steps' => steps).steps
    end

    context 'with control characters in step output' do
      let(:pretty) { false }
      let(:steps) do
        [
          CircleCI::CLI::Response::Step.new(
            'actions' => [
              {
                'type' => 'test', 'name' => "Test\r\e[2K", 'status' => 'failed',
                'output_url' => 'https://circleci.com/output/123'
              }
            ]
          )
        ]
      end

      it 'escapes the action name and log while preserving colors and log line breaks' do
        allow(http).to receive(:request).with(have_attributes(path: '/output/123'))
          .and_yield(successful_log_response(JSON.generate([{ message: "first\r\nsecond\e[2K" }])))

        expect(subject).to eq("\e[0;31;49mTest\\x0D\\x1B[2K\e[0m\nfirst\nsecond\\x1B[2K\n")
      end
    end

    context 'with pretty option' do
      let(:pretty) { true }

      it 'groups steps by type and prints timed-out actions in red' do
        expected = <<~EXPECTED
          +--------------------+
          +--------------------+
          |       \e[0;32;49mbuild\e[0m        |
          +------------+-------+
          | Dependency | 01:01 |
          | \e[0;32;49mCheckout\e[0m   | 00:01 |
          +------------+-------+
          | \e[0;33;49mBuild\e[0m      | 00:25 |
          +------------+-------+
          |        \e[0;32;49mtest\e[0m        |
          +------------+-------+
          | \e[0;31;49mTest\e[0m       | 00:01 |
          | action log         |
          +--------------------+
          |       \e[0;32;49mdeploy\e[0m       |
          +------------+-------+
          | \e[0;90;49mDeploy\e[0m     |       |
          +------------+-------+
        EXPECTED
        expect(subject).to eq expected.strip
      end
    end

    context 'without pretty option' do
      let(:pretty) { false }

      it 'groups steps by type and prints timed-out actions in red' do
        expected = <<~EXPECTED
          Dependency
          \e[0;32;49mCheckout\e[0m
          \e[0;33;49mBuild\e[0m

          \e[0;31;49mTest\e[0m
          action log

          \e[0;90;49mDeploy\e[0m
        EXPECTED
        expect(subject).to eq expected
      end
    end
  end

  describe '#write_to' do
    let(:printer_class) do
      Class.new(described_class) do
        attr_reader :log_chunks

        def initialize(...)
          super
          @log_chunks = []
        end

        private

        def each_escaped_chunk(action)
          super do |chunk|
            @log_chunks << WeakRef.new(chunk) if chunk.bytesize > 1024
            yield chunk
          end
        end
      end
    end

    let(:steps) do
      actions = (1..3).map do |index|
        {
          'type' => 'test', 'name' => "Action #{index}", 'status' => 'failed',
          'output_url' => "https://circleci.com/log/#{index}"
        }
      end
      [CircleCI::CLI::Response::Step.new('actions' => actions)]
    end

    def log_lines(index, record)
      Array.new(64) { |line| "#{index}/#{record}/#{line} #{'界' * 40}" }
    end

    def stream_log(response, index)
      allow(response).to receive(:read_body) do |&read|
        read.call('[')
        32.times do |record|
          read.call(',') unless record.zero?
          json = JSON.generate(message: log_lines(index, record).join("\r\n")).b
          json.bytes.each_slice(1024) { |bytes| read.call(bytes.pack('C*')) }
        end
        read.call(']')
      end
    end

    [true, false].each do |pretty|
      it "releases large log chunks and preserves action and record order with pretty=#{pretty}" do
        printer = printer_class.new(steps, pretty:)
        client = CircleCI::CLI::Networking::HTTPClient

        Tempfile.create('step-output', encoding: Encoding::UTF_8) do |output|
          expect(client).to receive(:get_raw).exactly(3).times do |url, &read|
            index = url.split('/').last.to_i
            GC.start
            expect(printer.log_chunks.none?(&:weakref_alive?)).to be(true)
            expect(output.pos).to be > 200_000 if !pretty && index > 1

            response = Net::HTTPOK.new('1.1', '200', 'OK')
            stream_log(response, index)
            read.call(response)
          end

          printer.write_to(output)
          expect(printer.log_chunks.size).to eq(96)
          output.rewind
          actual = output.each_line.filter_map do |line|
            line[/\d+\/\d+\/\d+ 界+/]
          end
          expected = (1..3).flat_map { |index| 32.times.flat_map { |record| log_lines(index, record) } }
          expect(actual).to eq(expected)
        end
      end
    end
  end
end
