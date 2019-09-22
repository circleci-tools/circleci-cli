# frozen_string_literal: true

require 'spec_helper'

describe Circler::BuildCommand, type: :command do # rubocop:disable Metrics/BlockLength
  shared_examples_for 'a command show build information' do
    let(:expected_output) do
      <<~EXPECTED
        +-------+-------+
        +-------+-------+
        |     \e[0;32;49mbuild\e[0m     |
        +-------+-------+
        | \e[0;32;49mBuild\e[0m | 00:01 |
        +-------+-------+
        |     \e[0;32;49mtest\e[0m      |
        +-------+-------+
        | \e[0;32;49mTest\e[0m  | 00:01 |
        +-------+-------+
      EXPECTED
    end

    it 'should show build information' do
      allow(Circler::BuildCommand).to receive(:say) {}
      expect(Circler::BuildCommand).to receive(:say).with(expected_output.strip)
      Circler::BuildCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil) }
    let(:expected_url) { 'https://circleci.com/gh/unhappychoice/default_project_name_from_io' }
    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show build information'
  end

  context 'with project input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil) }
    let(:expected_url) { "https://circleci.com/gh/#{project_name}" }
    it_behaves_like 'a command show build information'
  end

  context 'with build input' do
    let(:options) { OpenStruct.new(project: nil, build: 5) }
    let(:expected_url) { 'https://circleci.com/gh/unhappychoice/default_project_name_from_io/5' }
    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show build information'
  end
end
