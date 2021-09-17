# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildsCommand, type: :command do
  shared_examples_for 'a command show builds information' do
    let(:expected_output) do
      <<~EXPECTED
        +--------------------------------------------------------------------+
        |             \e[0;32;49mRecent Builds / #{project_name}\e[0m              |
        +--------+---------+--------+--------+--------+----------+-----------+
        | Number | Status  | Branch | Author | Commit | Duration | StartTime |
        +--------+---------+--------+--------+--------+----------+-----------+
        | 1234   | \e[0;32;49msuccess\e[0m | \e[0;32;49mmaster\e[0m | user   | Commit | 00:01    | 100000    |
        +--------+---------+--------+--------+--------+----------+-----------+
      EXPECTED
    end

    it 'should show builds information' do
      allow(CircleCI::CLI::Command::BuildsCommand).to receive(:say) { nil }
      expect(CircleCI::CLI::Command::BuildsCommand).to receive(:say).with(expected_output.strip)
      CircleCI::CLI::Command::BuildsCommand.run(options)
    end
  end

  context 'with no input' do
    let(:rugged_response_branch_name) { nil }
    let(:project_name) { io_response_project_name }
    let(:options) { OpenStruct.new(project: nil, branch: nil, pretty: true) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show builds information'
  end

  context 'with project input' do
    let(:project_name) { 'user/project_from_option_' }
    let(:options) { OpenStruct.new(project: project_name, branch: nil, pretty: true) }

    it_behaves_like 'a command show builds information'
  end

  context 'with branch input' do
    let(:project_name) { io_response_project_name }
    let(:options) { OpenStruct.new(project: nil, branch: 'master', pretty: true) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show builds information'
  end
end
