# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Response::Step do
  describe '#status' do
    subject(:status) { described_class.new('actions' => actions).status }

    def action(status, end_time: '2026-11-23T00:00:00Z')
      { 'status' => status, 'end_time' => end_time }
    end

    context 'with a single canceled action' do
      let(:actions) { [action('canceled')] }

      it { is_expected.to eq('canceled') }
    end

    context 'with a running action alongside a canceled one' do
      let(:actions) { [action('running', end_time: nil), action('canceled')] }

      it 'remains running' do
        expect(status).to eq('running')
      end
    end

    context 'with a failed action alongside a canceled one' do
      let(:actions) { [action('failed'), action('canceled')] }

      it 'keeps failed taking precedence over canceled' do
        expect(status).to eq('failed')
      end
    end

    context 'with every action skipped' do
      let(:actions) { [action('not_run'), action('not_run')] }

      it 'remains not_run' do
        expect(status).to eq('not_run')
      end
    end

    context 'with a successful action' do
      let(:actions) { [action('success')] }

      it { is_expected.to eq('success') }
    end
  end
end
