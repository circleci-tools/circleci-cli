# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BaseCommand do
  describe '.reponame' do
    subject { CircleCI::CLI::Command::BaseCommand.reponame }

    before do
      mock_remotes = [double('Rugged::Remote', name: 'origin', url: remote_url)]
      mock_repo = double('Rugged::Repository', remotes: mock_remotes)
      allow(Rugged::Repository).to receive(:new).with('.').and_return(mock_repo)
    end

    context 'when git repository has a github remote' do
      let(:remote_url) { 'git@github.com:user/repository.git' }
      it 'extracts the reponame from the origin url' do
        expect(subject).to eq('user/repository')
      end
    end

    context 'when git repository has a github remote that contains a dot' do
      let(:remote_url) { 'git@github.com:user/example.com.git' }
      it 'extracts the reponame from the origin url, including the dot' do
        expect(subject).to eq('user/example.com')
      end
    end

    context 'when git repository has a non-github remote' do
      let(:remote_url) { 'git@bitbucket.org:user/repository.git' }
      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '.branch_name' do
    subject { described_class.branch_name }

    before do
      head = instance_double(Rugged::Reference, name: name, branch?: branch?)
      repo = double('Rugged::Repository', head: head)
      allow(Rugged::Repository).to receive(:new).with('.').and_return(repo)
    end

    context 'with a valid current branch' do
      let(:name) { 'branch' }
      let(:branch?) { true }

      it { is_expected.to eq(name) }
    end

    context 'with no current branch' do
      let(:name) { nil }
      let(:branch?) { false }

      it { is_expected.to be_nil }
    end
  end
end
