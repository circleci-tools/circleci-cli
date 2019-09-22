# frozen_string_literal: true

require 'spec_helper'

describe Circler::CancelCommand, type: :command do
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

    it 'should show build information' do
      allow(Circler::ProjectsCommand).to receive(:say) {}
      expect(Circler::ProjectsCommand).to receive(:say).with(expected_output.strip)
      Circler::ProjectsCommand.run(options)
    end
  end
end
