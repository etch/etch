#!/usr/bin/ruby -w

# Some of the tests involve DTD validation.  For that we need LibXML.
ENV['xmllib'] = 'libxml'

#
# Run all of the etch test cases
#

require 'test/unit'
Dir.chdir(File.dirname(__FILE__))
Dir.foreach('.') do |entry|
  next unless entry =~ /\.rb$/
  # Skip this file
  next if entry == 'alltests.rb'
  # And the shared file
  next if entry == 'etchtest.rb'

  require entry
end
