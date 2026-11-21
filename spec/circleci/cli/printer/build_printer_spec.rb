# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Printer::BuildPrinter, type: :printer do
  describe '#to_s' do
    subject { described_class.new(builds, 'unhappychoice/default_reponame_from_api', pretty: pretty).to_s }

    let(:builds) do
      [
        CircleCI::CLI::Response::Build.new(
          {
            'username' => 'unhappychoice',
            'reponame' => 'default_reponame_from_api',
            'status' => 'success',
            'build_num' => 1234,
            'branch' => 'master',
            'author_name' => 'unhappychoice',
            'build_time_millis' => 83_900,
            'start_time' => 100_000,
            'steps' => [
              {
                'status' => 'success',
                'actions' => [
                  { 'type' => 'build', 'name' => 'Build', 'status' => 'success', 'run_time_millis' => 300 }
                ]
              },
              {
                'status' => 'success',
                'actions' => [
                  { 'type' => 'test', 'name' => 'Test', 'status' => 'success', 'run_time_millis' => 22_200 }
                ]
              }
            ]
          }
        ),
        CircleCI::CLI::Response::Build.new(
          {
            'username' => 'unhappychoice',
            'reponame' => 'default_reponame_from_api',
            'status' => 'timedout',
            'build_num' => 1236,
            'branch' => 'master',
            'author_name' => 'unhappychoice',
            'start_time' => 120_000,
            'steps' => [
              {
                'status' => 'timedout',
                'actions' => [
                  { 'type' => 'build', 'name' => 'Build', 'status' => 'success', 'run_time_millis' => 1290 }
                ]
              }
            ]
          }
        )
      ]
    end

    [true, false].each do |pretty_output|
      context "with pretty set to #{pretty_output}" do
        let(:pretty) { pretty_output }
        let(:builds) do
          [
            CircleCI::CLI::Response::Build.new(
              'build_num' => 1234,
              'status' => 'success',
              'branch' => "main\e[0m",
              'subject' => "Fix café\r\e[2K\n\u009B"
            )
          ]
        end

        it 'escapes build metadata while keeping CLI status and branch colors' do
          expect(subject).to include(
            "\e[0;32;49msuccess\e[0m", "\e[0;32;49mmain\\x1B[0m\e[0m",
            'Fix café\x0D\x1B[2K\x0A\x9B'
          )
        end
      end
    end

    context 'with pretty option' do
      let(:pretty) { true }

      it 'prints builds with a red timed-out status and branch' do
        expected = <<~EXPECTED
          +----------------------------------------------------------------------------+
          |          \e[0;32;49mRecent Builds / unhappychoice/default_reponame_from_api\e[0m           |
          +--------+----------+--------+---------------+--------+----------+-----------+
          | Number | Status   | Branch | Author        | Commit | Duration | StartTime |
          +--------+----------+--------+---------------+--------+----------+-----------+
          | 1234   | \e[0;32;49msuccess\e[0m  | \e[0;32;49mmaster\e[0m | unhappychoice |        | 01:23    | 100000    |
          | 1236   | \e[0;31;49mtimedout\e[0m | \e[0;31;49mmaster\e[0m | unhappychoice |        |          | 120000    |
          +--------+----------+--------+---------------+--------+----------+-----------+
        EXPECTED
        expect(subject).to eq expected.strip
      end
    end

    context 'without pretty option' do
      let(:pretty) { false }

      context 'with ASCII and full-width branch names' do
        let(:builds) do
          %w[main 開発].map do |branch|
            CircleCI::CLI::Response::Build.new(
              'build_num' => 1234, 'status' => 'success', 'branch' => branch, 'author_name' => 'unhappychoice'
            )
          end
        end

        it 'aligns the author column in terminal cells after colored branches' do
          expect(subject).to include("\e[0;32;49mmain\e[0m", "\e[0;32;49m開発\e[0m")
          author_columns = subject.lines.map do |line|
            prefix = line.partition('unhappychoice').first.gsub(/\e\[[\d;]*m/, '')
            Unicode::DisplayWidth.of(prefix)
          end
          expect(author_columns).to eq([21, 21])
        end
      end

      context 'with an uncolored build' do
        let(:builds) do
          super() + [CircleCI::CLI::Response::Build.new(
            'build_num' => 1237, 'status' => 'running', 'branch' => 'master', 'author_name' => 'unhappychoice'
          )]
        end

        it 'aligns columns by visible width' do
          expect(subject.lines.last).to start_with('1237  running   master  unhappychoice')
        end
      end

      it 'prints aligned builds with a blank duration for the timed-out build' do
        expected = <<~EXPECTED
          1234  \e[0;32;49msuccess\e[0m   \e[0;32;49mmaster\e[0m  unhappychoice    01:23  100000
          1236  \e[0;31;49mtimedout\e[0m  \e[0;31;49mmaster\e[0m  unhappychoice           120000
        EXPECTED
        expect(subject).to eq expected.strip
      end

      context 'with no builds' do
        let(:builds) { [] }

        it 'prints an empty string' do
          expect(subject).to eq('')
        end
      end
    end
  end
end
