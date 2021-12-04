# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Printer::ProjectPrinter, type: :printer do
  describe '#to_s' do
    subject { described_class.new(projects, pretty: pretty).to_s }

    let(:projects) do
      [
        CircleCI::CLI::Response::Project.new({ 'username' => 'user1', 'reponame' => 'repository1' }),
        CircleCI::CLI::Response::Project.new({ 'username' => 'user2', 'reponame' => 'repository2' }),
        CircleCI::CLI::Response::Project.new({ 'username' => 'user1', 'reponame' => 'repository3' }),
        CircleCI::CLI::Response::Project.new({ 'username' => 'user2', 'reponame' => 'repository4' }),
        CircleCI::CLI::Response::Project.new({ 'username' => 'user3', 'reponame' => 'repository5' })
      ]
    end

    context 'with pretty option' do
      let(:pretty) { true }

      it 'prints steps' do
        expected = <<~EXPECTED
          +-----------------------------+
          |          \e[0;32;49mProjects\e[0m           |
          +-----------+-----------------+
          | User name | Repository name |
          +-----------+-----------------+
          | user1     | repository1     |
          | user2     | repository2     |
          | user1     | repository3     |
          | user2     | repository4     |
          | user3     | repository5     |
          +-----------+-----------------+
        EXPECTED
        expect(subject).to eq expected.strip
      end
    end

    context 'without pretty option' do
      let(:pretty) { false }

      it 'prints steps' do
        expected = <<~EXPECTED
          user1/repository1
          user1/repository3
          user2/repository2
          user2/repository4
          user3/repository5
        EXPECTED
        expect(subject).to eq expected.strip
      end
    end
  end
end
