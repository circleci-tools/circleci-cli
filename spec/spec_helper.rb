# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.add_filter ['spec']
  SimpleCov.minimum_coverage line: 99
  SimpleCov.start
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'circleci_cli'
require 'ostruct'

Dir[File.join(File.expand_path('./', __dir__), 'support', '**', '*.rb')].each { |f| require f }
