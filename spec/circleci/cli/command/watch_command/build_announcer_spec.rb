# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildAnnouncer do
  let(:build) { instance_double(CircleCI::CLI::Response::Build, project_name: 'user/repo', build_number: 1234) }
  let(:puts_calls) { [] }
  let(:bordered_calls) { [] }
  let(:verbose) { false }
  let(:announcer) do
    described_class.new(
      build, verbose:, puts: ->(text) { puts_calls << text }, bordered: ->(text) { bordered_calls << text }
    )
  end

  describe '#notify_stopped' do
    it 'prints a known completion status as a plain colorized line' do
      announcer.notify_stopped('success')

      expect(puts_calls).to eq([CircleCI::CLI::Printer.colorize_green('🎉 user/repo #1234 has succeeded!')])
      expect(bordered_calls).to be_empty
    end

    it 'falls back to a generic message for an unrecognized status' do
      announcer.notify_stopped('retried')

      expect(puts_calls).to eq(['user/repo #1234 finished (status: retried).'])
    end

    it 'falls back to a generic message when the status is nil' do
      announcer.notify_stopped(nil)

      expect(puts_calls).to eq(['user/repo #1234 finished (status: unknown).'])
    end

    context 'with verbose output' do
      let(:verbose) { true }

      it 'prints the completion message inside a border instead of a plain line' do
        announcer.notify_stopped('failed')

        expect(bordered_calls).to eq([CircleCI::CLI::Printer.colorize_red('😥 user/repo #1234 has failed...')])
        expect(puts_calls).to be_empty
      end
    end
  end
end
