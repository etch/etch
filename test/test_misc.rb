#!/usr/bin/ruby -w

#
# Test miscellaneous items that don't fit elsewhere
#

require "./#{File.dirname(__FILE__)}/etchtest"
require 'webrick'

class EtchMiscTests < Test::Unit::TestCase
  include EtchTests

  def setup
    # Generate a file to use as our etch target/destination
    @targetfile = released_tempfile
    #puts "Using #{@targetfile} as target file"
    
    # Generate a directory for our test repository
    @repodir = initialize_repository
    @server = get_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testroot = tempdir
    #puts "Using #{@testroot} as client working directory"
  end
  
  def test_empty_repository
    # Does etch behave properly if the repository is empty?  I.e. no source or
    # commands directories.
    testname = 'empty repository'
    run_etch(@server, @testroot, :testname => testname)
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end

