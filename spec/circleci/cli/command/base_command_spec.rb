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
end
