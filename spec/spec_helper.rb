# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'circler'

Dir[File.join(File.expand_path('./', __dir__), 'support', '**', '*.rb')].each { |f| require f }
