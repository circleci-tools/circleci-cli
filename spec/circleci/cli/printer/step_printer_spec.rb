# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Printer::StepPrinter, type: :printer do
  describe '#to_s' do
    subject { described_class.new(steps, pretty: pretty).to_s }

    before do
      allow_any_instance_of(CircleCI::CLI::Response::Action).to receive(:log) { 'action log' }
    end

    let(:steps) do
      [
        CircleCI::CLI::Response::Step.new(
          'build',
          {
            'status' => 'success',
            'actions' => [
              { 'type' => 'build', 'name' => 'Dependency', 'status' => 'ok', 'run_time_millis' => 1200 },
              { 'type' => 'build', 'name' => 'Build', 'status' => 'canceled', 'run_time_millis' => 25_000 }
            ]
          }
        ),
        CircleCI::CLI::Response::Step.new(
          'test',
          {
            'status' => 'success',
            'actions' => [
              { 'type' => 'test', 'name' => 'Test', 'status' => 'failed', 'run_time_millis' => 1_200 }
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

    context 'with pretty option' do
      let(:pretty) { true }

      it 'prints steps' do
        expected = <<~EXPECTED
          +--------------------+
          +--------------------+
          |       \e[0;32;49mbuild\e[0m        |
          +------------+-------+
          | Dependency | 00:01 |
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

      it 'prints steps' do
        expected = <<~EXPECTED
          Dependency
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
