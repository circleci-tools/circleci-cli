# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildCommand, type: :command do
  shared_examples_for 'a command show build information' do
    let(:expected_output) do
      <<~EXPECTED
        +---------------+
        +---------------+
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
      allow(CircleCI::CLI::Command::BuildCommand).to receive(:say) { nil }
      expect(CircleCI::CLI::Command::BuildCommand).to receive(:say).with(expected_output.strip)
      CircleCI::CLI::Command::BuildCommand.run(options)
    end
  end

  context 'with no input' do
    let(:options) { OpenStruct.new(project: nil, build: nil, pretty: true) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show build information'
  end

  context 'with project input' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil, pretty: true) }

    it_behaves_like 'a command show build information'
  end

  context 'with build input' do
    let(:options) { OpenStruct.new(project: nil, build: 5, pretty: true) }

    it_behaves_like 'a command asks project name'
    it_behaves_like 'a command show build information'
  end

  context 'with last option' do
    let(:project_name) { 'unhappychoice/Circler' }
    let(:options) { OpenStruct.new(project: project_name, build: nil, last: true, pretty: true) }

    it_behaves_like 'a command show build information'
  end

  context 'with a failed action log' do
    let(:options) { OpenStruct.new(project: 'unhappychoice/Circler', build: 5, pretty: pretty) }
    let(:output_url) { 'https://circleci.com/output/123' }
    let(:long_line) { "#{'a' * 120}tail" }

    before do
      build_hash['steps'].last['actions'].first.merge!('status' => 'failed', 'output_url' => output_url)
      allow(CircleCI::CLI::Networking::HTTPClient).to receive(:get).with(output_url)
        .and_return([{ 'message' => "before\n\nafter\n#{long_line}\n" }])
    end

    context 'with table output' do
      let(:pretty) { true }

      it 'preserves blank rows and wraps long lines' do
        expect(described_class).to receive(:say) do |output|
          rows = output.lines.map { |line| line.split('|')[1]&.strip }
          expect(rows.drop_while { |row| row != 'before' }.take(5)).to eq(['before', '', 'after', 'a' * 120, 'tail'])
        end
        described_class.run(options)
      end
    end

    context 'with compact output' do
      let(:pretty) { false }

      it 'preserves blank lines and leaves long lines intact' do
        expect(described_class).to receive(:say).with(end_with("before\n\nafter\n#{long_line}\n"))
        described_class.run(options)
      end
    end
  end
end
