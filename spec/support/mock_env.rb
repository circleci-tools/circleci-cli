# frozen_string_literal: true

shared_context 'mock env' do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('CIRCLE_CI_TOKEN') { nil }
  end
end

RSpec.configure do |config|
  config.include_context 'mock env'
end
