# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::ProjectsCommand, type: :command do
  context 'with no input' do
    let(:options) { OpenStruct.new(token: nil) }
    let(:expected_output) do
      <<~EXPECTED
        +---------------+---------------------------+
        |                 \e[0;32;49mProjects\e[0m                  |
        +---------------+---------------------------+
        | User name     | Repository name           |
        +---------------+---------------------------+
        | unhappychoice | default_reponame_from_api |
        +---------------+---------------------------+
      EXPECTED
    end

    it 'should show projects' do
      allow(CircleCI::CLI::Command::ProjectsCommand).to receive(:say) {}
      expect(CircleCI::CLI::Command::ProjectsCommand).to receive(:say).with(expected_output.strip)
      CircleCI::CLI::Command::ProjectsCommand.run(options)
    end
  end
end
