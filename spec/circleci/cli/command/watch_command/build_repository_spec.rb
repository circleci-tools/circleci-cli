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

    it 'encodes the branch in the refresh request and matches builds against the original name' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:start).and_yield(http)
      allow_any_instance_of(CircleCi::Project).to receive(:recent_builds_branch).and_call_original
      path = "/api/v1.1/project/github/#{build.username}/#{build.reponame}/tree/release%231"
      payload = build_hash.merge('branch' => 'release#1', 'build_num' => 1235)
      expect(http).to receive(:request).with(having_attributes(uri: having_attributes(path: path)), nil)
                                       .and_return(instance_double(Net::HTTPOK, body: JSON.generate([payload])))

      repository = described_class.new(build.username, build.reponame, branch: 'release#1')
      repository.update

      expect(repository.builds_to_show).to contain_exactly(having_attributes(branch: 'release#1', build_number: 1235))
    end
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
