# frozen_string_literal: true

shared_context 'mock io' do
  let(:io_response_circle_ci_token) { 'circle-ci-token' }
  let(:io_response_project_name) { 'user/project_name_from_io' }
  let(:io_response_build_number) { 1234 }

  before do
    ObjectSpace.each_object(Class).select { |klass| klass < CircleCI::CLI::Command::BaseCommand }.each do |klass|
      allow(klass).to receive(:ask).with('Circle CI token ? :') { io_response_circle_ci_token }
      allow(klass).to receive(:ask).with('Input user-name/project-name :') { io_response_project_name }
      allow(klass).to receive(:ask).with('Input build number') { io_response_build_number }
      allow(klass).to receive(:reponame) { nil }
    end
  end
end

RSpec.configure do |config|
  config.include_context 'mock io', type: :command
end
