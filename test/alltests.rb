#!/usr/bin/ruby -w

#
# Run all of the etch test cases
#

require 'test/unit'
Dir.foreach('.') do |entry|
  next unless entry =~ /\.rb$/
  # Skip this file
  next if entry == 'alltests.rb'
  # And the shared file
  next if entry == 'etchtest.rb'

  require entry
end
