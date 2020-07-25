# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildRepository do
  let(:build) do
    CircleCI::CLI::Response::Build.new(
      {
        'username' => 'unhappychoice',
        'reponame' => 'default_reponame_from_api',
        'status' => 'running',
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
    )
  end

  before do
    allow(CircleCI::CLI::Response::Build).to receive(:all) { [build] }
  end

  describe '#update' do
    subject { CircleCI::CLI::Command::BuildRepository.new(build.username, build.reponame).update }

    it { is_expected.to match_array [build] }
  end

  describe '#mark_as_shown' do
    subject do
      CircleCI::CLI::Command::BuildRepository.new(build.username, build.reponame).mark_as_shown(build.build_number)
    end

    it { is_expected.to match_array [build.build_number] }
  end

  describe '#builds_to_show' do
    subject { CircleCI::CLI::Command::BuildRepository.new(build.username, build.reponame).builds_to_show }

    it { is_expected.to match_array [build] }
  end

  describe '#build_for' do
    subject do
      CircleCI::CLI::Command::BuildRepository.new(build.username, build.reponame).build_for(build.build_number)
    end

    it { is_expected.to eq build }
  end
end
