# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redis-lock/version'

Gem::Specification.new do |gem|
  gem.name          = "bfg-redis-lock"
  gem.version       = Redis::Lock::VERSION
  gem.authors       = ["Stuart Garner"]
  gem.email         = ["stuart@biddingforgood.com"]
  gem.summary       = %q{A pessimistic redis lock implementation.'}
  gem.description   = <<-DESC
    A pessimistic redis lock implementation that doesn't use timestamps, works with the latest redis client, and properly handles removing locks.
  DESC
  gem.homepage      = "https://github.com/BiddingForGood/redis-lock"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  
  gem.add_dependency "redis", "~> 3.0.0"

  gem.add_development_dependency "rake", "~> 0.9.2"
  gem.add_development_dependency "rspec", "~> 2.12.0"
end
