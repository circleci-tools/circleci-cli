# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.add_filter ['spec']
  SimpleCov.start
end

if ENV['CODECOV_TOKEN']
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'circleci_cli'

Dir[File.join(File.expand_path('./', __dir__), 'support', '**', '*.rb')].sort.each { |f| require f }
