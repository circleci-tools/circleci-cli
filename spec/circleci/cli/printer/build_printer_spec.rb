# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Printer::BuildPrinter, type: :printer do
  describe '#to_s' do
    subject { described_class.new(builds, builds.first.project_name, pretty: pretty).to_s }

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
            'status' => 'failed',
            'build_num' => 1236,
            'branch' => 'master',
            'author_name' => 'unhappychoice',
            'build_time_millis' => 9_300,
            'start_time' => 120_000,
            'steps' => [
              {
                'status' => 'failed',
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

      it 'prints steps' do
        expected = <<~EXPECTED
          +---------------------------------------------------------------------------+
          |          \e[0;32;49mRecent Builds / unhappychoice/default_reponame_from_api\e[0m          |
          +--------+---------+--------+---------------+--------+----------+-----------+
          | Number | Status  | Branch | Author        | Commit | Duration | StartTime |
          +--------+---------+--------+---------------+--------+----------+-----------+
          | 1234   | \e[0;32;49msuccess\e[0m | \e[0;32;49mmaster\e[0m | unhappychoice |        | 00:23    | 100000    |
          | 1236   | \e[0;31;49mfailed\e[0m  | \e[0;31;49mmaster\e[0m | unhappychoice |        | 00:09    | 120000    |
          +--------+---------+--------+---------------+--------+----------+-----------+
        EXPECTED
        expect(subject).to eq expected.strip
      end
    end

    context 'without pretty option' do
      let(:pretty) { false }

      it 'prints steps' do
        expected = <<~EXPECTED
          1234  \e[0;32;49msuccess\e[0m  \e[0;32;49mmaster\e[0m  unhappychoice    00:23  100000
          1236  \e[0;31;49mfailed\e[0m   \e[0;31;49mmaster\e[0m  unhappychoice    00:09  120000
        EXPECTED
        expect(subject).to eq expected.strip
      end
    end
  end
end
