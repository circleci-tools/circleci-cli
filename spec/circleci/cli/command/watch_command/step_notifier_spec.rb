# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::StepNotifier do
  let(:puts_calls) { [] }
  let(:bordered_calls) { [] }
  let(:notifier) do
    described_class.new(
      verbose:, puts: ->(text) { puts_calls << text }, bordered: ->(text) { bordered_calls << text }
    )
  end
  let(:verbose) { false }

  def step(name:, status:, identity: [0, 1])
    instance_double(CircleCI::CLI::Response::Step, name:, status:, identity:)
  end

  describe '#on_new_step' do
    context 'without verbose output' do
      it 'prints a running step as a plain line' do
        notifier.on_new_step(step(name: 'Build', status: 'running'))

        expect(puts_calls).to eq(['Build'])
      end

      it 'prints a finished step colorized without a rewrite prefix' do
        notifier.on_new_step(step(name: 'Build', status: 'success'))

        expect(puts_calls).to eq(["\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Build')}"])
      end
    end

    context 'with verbose output' do
      let(:verbose) { true }

      it 'prints the step name inside a border instead of a plain line' do
        notifier.on_new_step(step(name: 'Build', status: 'running'))

        expect(bordered_calls).to eq(['Build'])
        expect(puts_calls).to be_empty
      end
    end
  end

  describe '#on_new_step_status' do
    it 'does nothing while the step is still running' do
      notifier.on_new_step_status(step(name: 'Build', status: 'running'))

      expect(puts_calls).to be_empty
    end

    context 'with verbose output' do
      let(:verbose) { true }

      it 'does nothing since verbose steps are only announced via on_new_step' do
        notifier.on_new_step_status(step(name: 'Build', status: 'success'))

        expect(puts_calls).to be_empty
        expect(bordered_calls).to be_empty
      end
    end

    context 'when the step was the last one printed' do
      it 'rewrites the previous line in place' do
        notifier.on_new_step(step(name: 'Build', status: 'running'))
        notifier.on_new_step_status(step(name: 'Build', status: 'success'))

        expect(puts_calls.last).to eq("\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Build')}")
      end
    end

    context 'when another step has been printed since' do
      it 'appends a new line instead of rewriting' do
        notifier.on_new_step(step(name: 'Build', status: 'running', identity: [0, 1]))
        notifier.on_new_step(step(name: 'Test', status: 'running', identity: [0, 2]))
        notifier.on_new_step_status(step(name: 'Build', status: 'success', identity: [0, 1]))

        expect(puts_calls.last).to eq("\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Build')}")
      end
    end
  end

  describe '#notify_step_change' do
    it 'treats a step with no previous status as newly observed' do
      notifier.notify_step_change(step(name: 'Build', status: 'running'), nil)

      expect(puts_calls).to eq(['Build'])
    end

    it 'does nothing when the status has not changed' do
      notifier.notify_step_change(step(name: 'Build', status: 'running'), 'running')

      expect(puts_calls).to be_empty
    end

    it 'notifies a status transition' do
      notifier.notify_step_change(step(name: 'Build', status: 'success'), 'running')

      expect(puts_calls).to eq(["\e[1A\e[2K\r#{CircleCI::CLI::Printer.colorize_green('Build')}"])
    end
  end

  describe '#disable_step_line_rewrites' do
    it 'appends the status instead of rewriting the previous line' do
      notifier.on_new_step(step(name: 'Build', status: 'running'))
      notifier.disable_step_line_rewrites
      notifier.on_new_step_status(step(name: 'Build', status: 'success'))

      expect(puts_calls.last).to eq(CircleCI::CLI::Printer.colorize_green('Build'))
    end
  end
end
