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
            'build_time_millis' => 23_900,
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
            'build_time_millis' => 9_300,
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

    context 'with pretty option' do
      let(:pretty) { true }

      it 'prints builds with a red timed-out status and branch' do
        expected = <<~EXPECTED
          +----------------------------------------------------------------------------+
          |          \e[0;32;49mRecent Builds / unhappychoice/default_reponame_from_api\e[0m           |
          +--------+----------+--------+---------------+--------+----------+-----------+
          | Number | Status   | Branch | Author        | Commit | Duration | StartTime |
          +--------+----------+--------+---------------+--------+----------+-----------+
          | 1234   | \e[0;32;49msuccess\e[0m  | \e[0;32;49mmaster\e[0m | unhappychoice |        | 00:23    | 100000    |
          | 1236   | \e[0;31;49mtimedout\e[0m | \e[0;31;49mmaster\e[0m | unhappychoice |        | 00:09    | 120000    |
          +--------+----------+--------+---------------+--------+----------+-----------+
        EXPECTED
        expect(subject).to eq expected.strip
      end
    end

    context 'without pretty option' do
      let(:pretty) { false }

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

      it 'prints aligned builds with a red timed-out status and reads information once per build' do
        builds.each { |build| expect(build).to receive(:information).once.and_call_original }

        expected = <<~EXPECTED
          1234  \e[0;32;49msuccess\e[0m   \e[0;32;49mmaster\e[0m  unhappychoice    00:23  100000
          1236  \e[0;31;49mtimedout\e[0m  \e[0;31;49mmaster\e[0m  unhappychoice    00:09  120000
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
