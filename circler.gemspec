# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'circler/version'

Gem::Specification.new do |spec|
  spec.name          = "circler"
  spec.version       = Circler::VERSION
  spec.authors       = ["unhappychoice"]
  spec.email         = ["unhappychoice@gmail.com"]

  spec.summary       = %q{CLI tool for Circle CI}
  spec.description   = %q{A command line tool for circle ci}
  spec.homepage      = "https://github.com/unhappychoice/circler"
  spec.license       = "MIT"
  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Production
  spec.add_dependency 'pusher-client', '~> 0.6.2'
  spec.add_dependency 'thor', '~> 0.19.1'
  spec.add_dependency 'faraday', '~> 0.9.2'
  spec.add_dependency 'launchy', '~> 2.4.3'
  spec.add_dependency 'circleci', '~> 0.2.0'
  spec.add_dependency 'rugged', '~> 0.24.0b11'
  spec.add_dependency 'terminal-table', '~> 1.5.2'
  spec.add_dependency 'highline', '~> 1.7.8'
  spec.add_dependency 'colorize', '~> 0.7.7'
  spec.add_dependency 'terminal-notifier', '~> 1.6.3'

  # Development
  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end
