#!/usr/bin/ruby -w

#
# Test output capturing
#

require "./#{File.dirname(__FILE__)}/etchtest"
require 'timeout'
$:.unshift(File.join(EtchTests::CLIENTDIR, 'lib'))
$:.unshift(File.join(EtchTests::SERVERDIR, 'lib'))
require 'etch/client'

class EtchOutputCaptureTests < Test::Unit::TestCase
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
  
  def test_output_capture
    #
    # Run a test where a post command outputs something, make sure that output
    # is reported to the server.
    #
    testname = 'output capture'
    
    postoutput = "This is output from\nthe post\ncommand"
    postcmd = Tempfile.new('etchoutputtest')
    postcmd.puts '#!/bin/sh'
    # echo may or may not add a trailing \n depending on which echo we end
    # up, so use printf, which doesn't add things.
    postcmd.puts "printf \"#{postoutput}\""
    postcmd.close
    File.chmod(0755, postcmd.path)
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <exec>#{postcmd.path}</exec>
          </post>
        </config>
      EOF
    end
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    assert_match(postoutput, latest_result_message, testname)
  end
  
  def test_output_capture_timeout
    #
    # Run a test where a post command does not properly daemonize, ensure that
    # etch eventually times out.
    #
    testname = 'output capture timeout'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <exec>#{RUBY} -e 'sleep #{Etch::Client::OUTPUT_CAPTURE_TIMEOUT + 30}' &amp;</exec>
          </post>
        </config>
      EOF
    end
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    begin
      Timeout.timeout(Etch::Client::OUTPUT_CAPTURE_TIMEOUT + 15) do
        # NOTE: This test is not normally run because the timeout is so long. 
        # Uncomment this run_etch line to run this test.
        #
        #run_etch(@server, @testroot, :testname => testname)
      end
    rescue Timeout::Error
      flunk('output capturing did not time out as expected')
    end
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end
