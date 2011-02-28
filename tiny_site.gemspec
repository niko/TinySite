# encoding: utf-8

$:.unshift File.expand_path('../lib', __FILE__)
require 'tiny_site/version'

Gem::Specification.new do |s|
  s.name         = "tiny_site"
  s.version      = TinySite::VERSION
  s.authors      = ["Niko Dittmann"]
  s.email        = "mail+git@niko-dittmann.com"
  s.homepage     = "https://github.com/niko/TinySite"
  s.summary      = "A small static site engine with Heroku and Dropbox in mind"
  s.description  = s.summary

  s.files        = Dir['lib/**/*.rb']
  s.platform     = Gem::Platform::RUBY
  
  s.add_dependency('rack')
  s.add_dependency('RedCloth')
  s.add_dependency('haml')
  
  s.add_development_dependency('rspec')
  
  s.require_path = 'lib'
  s.rubyforge_project = '[none]'
end
