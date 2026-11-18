# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::ProjectsCommand, type: :command do
  context 'with no input' do
    let(:options) { OpenStruct.new(token: nil, pretty: true) }
    let(:expected_output) do
      <<~EXPECTED
        +-------------------------------------------+
        |                 \e[0;32;49mProjects\e[0m                  |
        +---------------+---------------------------+
        | User name     | Repository name           |
        +---------------+---------------------------+
        | unhappychoice | default_reponame_from_api |
        +---------------+---------------------------+
      EXPECTED
    end

    it 'should show projects' do
      expect { described_class.run(options) }.to output(a_string_including(expected_output)).to_stdout
    end
  end
end
