# frozen_string_literal: true

require 'spec_helper'

describe CircleCI::CLI::Command::BuildWatcher do
  let(:build) do
    CircleCI::CLI::Response::Build.new(
      {
        'username' => 'unhappychoice',
        'reponame' => 'default_reponame_from_api',
        'status' => 'success',
        'build_num' => 1234,
        'branch' => 'master',
        'author_name' => 'unhappychoice',
        'subject' => 'Commit',
        'build_time_millis' => 1000,
        'start_time' => 100_000,
        'steps' => [
          {
            'status' => 'success',
            'actions' => [{ 'type' => 'build', 'name' => 'Build', 'status' => 'success', 'run_time_millis' => 1000 }]
          },
          {
            'status' => 'success',
            'actions' => [{ 'type' => 'test', 'name' => 'Test', 'status' => 'success', 'run_time_millis' => 1000 }]
          }
        ]
      }
    )
  end

  describe '#start' do
    subject { described_class.new(build, verbose: verbose).start }

    before do
      expect_any_instance_of(CircleCI::CLI::Networking::CircleCIPusherClient)
        .to receive(:bind_event_json).with(build.channel_name, 'newAction')
      expect_any_instance_of(CircleCI::CLI::Networking::CircleCIPusherClient)
        .to receive(:bind_event_json).with(build.channel_name, 'appendAction')
      expect_any_instance_of(CircleCI::CLI::Networking::CircleCIPusherClient)
        .to receive(:bind_event_json).with(build.channel_name, 'updateAction')

      expect_any_instance_of(described_class).to receive(:say).with(expected.strip)
    end

    context 'with verbose option' do
      let(:verbose) { true }
      let(:expected) do
        <<~EXPECTED
          +----------------------------------------------------------------------------------------------------------------------+
          |                           👀 Start watching unhappychoice/default_reponame_from_api #1234                            |
          +----------------------------------------------------------------------------------------------------------------------+
          | Project:  unhappychoice/default_reponame_from_api                                                                    |
          | Build:    1234                                                                                                       |
          | Author:   unhappychoice                                                                                              |
          | Workflow: /                                                                                                          |
          +----------------------------------------------------------------------------------------------------------------------+
        EXPECTED
      end

      it 'prints build information' do
        subject
      end
    end

    context 'without verbose option' do
      let(:verbose) { false }
      let(:expected) do
        <<~EXPECTED
          +----------------------------------------------------------------------------------------------------------------------+
          |                           👀 Start watching unhappychoice/default_reponame_from_api #1234                            |
          +----------------------------------------------------------------------------------------------------------------------+
          | Project:  unhappychoice/default_reponame_from_api                                                                    |
          | Build:    1234                                                                                                       |
          | Author:   unhappychoice                                                                                              |
          | Workflow: /                                                                                                          |
          +----------------------------------------------------------------------------------------------------------------------+
        EXPECTED
      end

      it 'prints build information' do
        subject
      end
    end
  end

  describe '#stop' do
    subject { described_class.new(build, verbose: verbose).stop(status) }

    before do
      expect_any_instance_of(CircleCI::CLI::Networking::CircleCIPusherClient)
        .to receive(:unsubscribe).with("#{build.channel_name}@0")
    end

    context 'with verbose option' do
      let(:verbose) { true }

      context 'when status is success' do
        let(:status) { 'success' }

        it 'prints message' do
          expected = <<~EXPECTED
            +----------------------------------------------------------------------------------------------------------------------+
            | \e[0;32;49m🎉 unhappychoice/default_reponame_from_api #1234 has succeeded!\e[0m                                                      |
            +----------------------------------------------------------------------------------------------------------------------+
          EXPECTED
          expect_any_instance_of(described_class).to receive(:say).with(expected.strip)

          subject
        end
      end

      context 'when status is failed' do
        let(:status) { 'failed' }

        it 'prints message' do
          expected = <<~EXPECTED
            +----------------------------------------------------------------------------------------------------------------------+
            | \e[0;31;49m😥 unhappychoice/default_reponame_from_api #1234 has failed...\e[0m                                                       |
            +----------------------------------------------------------------------------------------------------------------------+
          EXPECTED
          expect_any_instance_of(described_class).to receive(:say).with(expected.strip)

          subject
        end
      end
    end

    context 'without verbose option' do
      let(:verbose) { false }

      context 'when status is success' do
        let(:status) { 'success' }

        it 'prints message' do
          expect_any_instance_of(described_class)
            .to receive(:say).with("\e[0;32;49m🎉 unhappychoice/default_reponame_from_api #1234 has succeeded!\e[0m")

          subject
        end
      end

      context 'when status is failed' do
        let(:status) { 'failed' }

        it 'prints message' do
          expect_any_instance_of(described_class)
            .to receive(:say).with("\e[0;31;49m😥 unhappychoice/default_reponame_from_api #1234 has failed...\e[0m")

          subject
        end
      end
    end
  end

  context 'with pusher events' do
    subject { described_class.new(build, verbose: verbose).start }

    let(:new_actions) { [{ 'log' => { 'name' => 'new action' } }] }
    let(:append_actions) { [{ 'step' => 'step1', 'out' => { 'message' => 'append action' } }] }
    let(:update_actions) { [{ 'step' => 'step1', 'log' => { 'status' => 'failed', 'name' => 'update action' } }] }

    before do
      allow_any_instance_of(described_class).to receive(:notify_started)

      allow_any_instance_of(CircleCI::CLI::Networking::CircleCIPusherClient)
        .to receive(:bind_event_json).with(build.channel_name, 'newAction').and_yield(*new_actions)
      allow_any_instance_of(CircleCI::CLI::Networking::CircleCIPusherClient)
        .to receive(:bind_event_json).with(build.channel_name, 'appendAction').and_yield(*append_actions)
      allow_any_instance_of(CircleCI::CLI::Networking::CircleCIPusherClient)
        .to receive(:bind_event_json).with(build.channel_name, 'updateAction').and_yield(*update_actions)
    end

    context 'with verbose option' do
      let(:verbose) { true }

      it 'prints log name' do
        expected = <<~EXPECTED
          +----------------------------------------------------------------------------------------------------------------------+
          | new action                                                                                                           |
          +----------------------------------------------------------------------------------------------------------------------+
        EXPECTED
        allow_any_instance_of(described_class).to receive(:say).with(expected.strip)
        allow_any_instance_of(Thor::Shell::Basic).to receive(:say).with('append action', nil, false)

        subject
      end
    end

    context 'without verbose option' do
      let(:verbose) { false }

      it 'prints log name' do
        allow_any_instance_of(described_class).to receive(:print).with('new action')
        allow_any_instance_of(described_class).to receive(:puts).with("\e[2K\r\e[0;31;49mupdate action\e[0m")
        allow_any_instance_of(described_class).to receive(:say).with('append action')
        subject
      end
    end
  end
end
