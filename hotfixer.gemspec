# -*- encoding: utf-8 -*-
require File.expand_path('../lib/hotfixer/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jeff Bruns"]
  gem.email         = ["jscottbruns@gmail.com"]
  gem.description   = gem.summary = "Simple tool for performing hotfixes on AWS opsworks"
  gem.homepage      = ""
  gem.license       = "LGPL-3.0"

  gem.executables   = ['hotfixer']
  gem.files         = `git ls-files | grep -Ev '^(myapp|examples)'`.split("\n")
  gem.test_files    = `git ls-files -- test/*`.split("\n")
  gem.name          = "hotfixer"
  gem.require_paths = ["lib"]
  gem.version       = Hotfixer::VERSION
  gem.add_dependency                  'aws-sdk', '~> 1.57.0'
  gem.add_dependency                  'net-ssh', '~> 2.9.1'
  gem.add_dependency                  'colored', '~> 1.2'
  gem.add_development_dependency      'minitest', '~> 5.3.3'
  gem.add_development_dependency      'rake'
end