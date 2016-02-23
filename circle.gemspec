# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'circle/version'

Gem::Specification.new do |spec|
  spec.name          = "circle"
  spec.version       = Circle::VERSION
  spec.authors       = ["unhappychoice"]
  spec.email         = ["unhappychoice@gmail.com"]

  spec.summary       = %q{TODO: Write a short summary, because Rubygems requires one.}
  spec.description   = %q{TODO: Write a longer description or delete this line.}
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Production
  spec.add_dependency 'thor', '~> 0.19.1'
  spec.add_dependency 'faraday', '~> 0.9.2'
  spec.add_dependency 'launchy', '~> 2.4.3'
  spec.add_dependency 'circleci', '~> 0.2.0'
  spec.add_dependency 'rugged', '~> 0.24.0b11'
  spec.add_dependency 'terminal-table', '~> 1.5.2'
  spec.add_dependency 'highline', '~> 1.7.8'
  spec.add_dependency 'colorize', '~> 0.7.7'

  # Development
  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end
