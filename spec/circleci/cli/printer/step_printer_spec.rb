# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Printer::StepPrinter, type: :printer do
  describe '#to_s' do
    subject { described_class.new(steps, pretty: pretty).to_s }

    let(:http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:start).with('circleci.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).with(an_instance_of(Net::HTTP::Get).and(have_attributes(path: '/output/123')))
        .and_return(instance_double(Net::HTTPOK, body: '[{"message":"action log"}]'))
      allow(http).to receive(:request).with(have_attributes(path: '/output/456'))
        .and_return(instance_double(Net::HTTPOK, body: '[{"message":"successful action log"}]'))
    end

    after do
      expect(http).to have_received(:request).with(have_attributes(path: '/output/123')).once
      expect(http).not_to have_received(:request).with(have_attributes(path: '/output/456'))
    end

    let(:steps) do
      [
        CircleCI::CLI::Response::Step.new(
          'build',
          {
            'status' => 'success',
            'actions' => [
              { 'type' => 'build', 'name' => 'Dependency', 'status' => 'ok', 'run_time_millis' => 1200 },
              {
                'type' => 'build', 'name' => 'Checkout', 'status' => 'success', 'run_time_millis' => 1200,
                'output_url' => 'https://circleci.com/output/456'
              }
            ]
          }
        ),
        CircleCI::CLI::Response::Step.new(
          'test',
          {
            'status' => 'success',
            'actions' => [
              {
                'type' => 'test', 'name' => 'Test', 'status' => 'timedout', 'run_time_millis' => 1_200,
                'output_url' => 'https://circleci.com/output/123'
              }
            ]
          }
        ),
        CircleCI::CLI::Response::Step.new(
          'build',
          {
            'status' => 'success',
            'actions' => [
              { 'type' => 'build', 'name' => 'Build', 'status' => 'canceled', 'run_time_millis' => 25_000 }
            ]
          }
        ),
        CircleCI::CLI::Response::Step.new(
          'deploy',
          {
            'status' => 'success',
            'actions' => [
              { 'type' => 'deploy', 'name' => 'Deploy', 'status' => 'no_tests', 'run_time_millis' => 30_200 }
            ]
          }
        )
      ]
    end

    context 'with control characters in step output' do
      let(:pretty) { false }
      let(:steps) do
        [
          CircleCI::CLI::Response::Step.new(
            'test',
            'actions' => [
              { 'name' => "Test\r\e[2K", 'status' => 'failed', 'output_url' => 'https://circleci.com/output/123' }
            ]
          )
        ]
      end

      it 'escapes the action name and log while preserving colors and log line breaks' do
        allow(http).to receive(:request).with(have_attributes(path: '/output/123'))
          .and_return(instance_double(Net::HTTPOK, body: JSON.generate([{ message: "first\r\nsecond\e[2K" }])))

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
          | Dependency | 00:01 |
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
          | \e[0;90;49mDeploy\e[0m     | 00:30 |
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
end
