# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'spec_helper'

RSpec.describe 'CLI startup' do
  it 'prints the version without loading OpenStruct' do
    script = <<~RUBY_CODE
      ARGV.replace(['version'])
      load './exe/circleci-cli'
      abort 'CLI loaded OpenStruct' if defined?(OpenStruct)
    RUBY_CODE

    output, errors, status = Open3.capture3(RbConfig.ruby, '-e', script, chdir: File.expand_path('..', __dir__))

    expect(status).to be_success, errors
    expect(output.chomp).to eq(CircleCI::CLI::VERSION)
  end
end
