# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Printer::EnvVarPrinter, type: :printer do
  describe '#to_s' do
    subject { described_class.new(env_vars, 'octocat/hello-world', pretty: pretty).to_s }

    let(:env_vars) do
      [
        CircleCI::CLI::Response::EnvVar.new('name' => 'FOO', 'value' => 'xxxx1234'),
        CircleCI::CLI::Response::EnvVar.new('name' => 'BAR', 'value' => 'xxxx5678')
      ]
    end

    context 'with pretty option' do
      let(:pretty) { true }

      it 'prints a table of masked environment variables' do
        expect(subject).to include(
          "\e[0;32;49mEnvironment Variables / octocat/hello-world\e[0m",
          'Name', 'Value', 'FOO', 'xxxx1234', 'BAR', 'xxxx5678'
        )
      end
    end

    context 'without pretty option' do
      let(:pretty) { false }

      it 'prints compact NAME=VALUE pairs' do
        expected = <<~EXPECTED
          FOO=xxxx1234
          BAR=xxxx5678
        EXPECTED
        expect(subject).to eq expected.strip
      end
    end
  end
end
