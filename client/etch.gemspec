# coding: utf-8
require 'rubygems/package_task'
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'etch/version'

spec = Gem::Specification.new do |s|
  s.name          = "etch"
  s.version       = Etch::Client::VERSION
  s.authors       = ["Jason Heiss"]
  s.email         = ["etch-users@lists.sourceforge.net"]

  s.summary       = %q{Etch system configuration management client}
  s.homepage      = "http://etch.github.io"
  s.license       = "MIT"

  s.files                  = `git ls-files -z bin/ lib/`.split("\x0")
  s.bindir                 = "bin"
  s.executables            = s.files.grep(%r{^#{s.bindir}/}) { |f| File.basename f }
  s.require_paths          = ["lib"]
  s.rubyforge_project      = "etchsyscm"
  s.platform               = Gem::Platform::RUBY
  s.required_ruby_version  = ">=1.8"

  s.add_dependency "facter", "~> 1.6", '>= 1.6.5'

  s.add_development_dependency "bundler", "~> 1.12"
  s.add_development_dependency "rake", "~> 10.0"
  s.add_development_dependency "minitest", "~> 5.0"
end

Gem::PackageTask.new(spec) do |pkg|
  pkg.package_dir = "pkg"
end

spec
