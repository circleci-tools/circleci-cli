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

    it 'updates builds from the branch endpoint when a branch is specified' do
      expect(CircleCI::CLI::Response::Build).to receive(:all)
        .with(build.username, build.reponame)
        .ordered
        .and_return([build])
      expect(CircleCI::CLI::Response::Build).to receive(:branch)
        .with(build.username, build.reponame, 'master')
        .ordered
        .and_return([build])

      repository = described_class.new(build.username, build.reponame, branch: 'master')

      expect(repository.update).to match_array([build])
    end

    it 'bounds retained builds and shown IDs as a fixed-size window advances' do
      repository = described_class.new(build.username, build.reponame)
      repository.watch(build.build_number)
      pending = finished_build(1)
      window = [pending, finished_build(2), finished_build(3)]
      allow(CircleCI::CLI::Response::Build).to receive(:all) { window }
      repository.update
      [2, 3].each { |number| repository.mark_as_shown(number) }

      (4..103).each do |number|
        window = window.drop(1) + [finished_build(number)]

        expect(repository.update).to match_array(window + [build, pending])
        expect(repository.builds_to_show.map(&:build_number)).to eq([pending.build_number, number])
        repository.mark_as_shown(number)
        expect(repository.instance_variable_get(:@build_numbers_shown).size).to eq(window.size)
      end

      expect(repository.build_for(build.build_number)).to eq(build)
      repository.mark_as_shown(pending.build_number)
      expect(repository.build_for(pending.build_number)).to be_nil
    end

    it 'retains a watched completion until it is acknowledged after leaving the window' do
      repository = described_class.new(build.username, build.reponame)
      repository.watch(build.build_number)
      completed = finished_build(build.build_number)
      allow(CircleCI::CLI::Response::Build).to receive(:all).and_return([completed], [])

      repository.update
      repository.update

      expect(repository.build_for(build.build_number)).to eq(completed)
      expect(repository.builds_to_show).to be_empty
      repository.mark_as_shown(build.build_number)
      expect(repository.build_for(build.build_number)).to be_nil
    end
  end

  describe '#mark_as_shown' do
    it 'suppresses a shown build across successive responses' do
      repository = described_class.new(build.username, build.reponame)
      completed = finished_build(build.build_number)
      allow(CircleCI::CLI::Response::Build).to receive(:all).and_return([completed])
      repository.update
      expect(repository.builds_to_show).to eq([completed])
      repository.mark_as_shown(completed.build_number)

      2.times do
        repository.update
        expect(repository.builds_to_show).to be_empty
      end
    end
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

  def finished_build(number)
    CircleCI::CLI::Response::Build.new('build_num' => number, 'status' => 'success')
  end
end
