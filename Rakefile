require 'rubygems' unless ENV['NO_RUBYGEMS']
require 'rspec/core/rake_task'

task :default => :spec

desc "Run specs"
RSpec::Core::RakeTask.new do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.rspec_opts = %w(-fs --color)
end
