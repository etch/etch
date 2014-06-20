#!/usr/bin/ruby -w

#
# Test output capturing
#

require File.expand_path('etchtest', File.dirname(__FILE__))
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
  
  def test_output_encoding
    #
    # Run a test where a post command outputs something outside the ASCII
    # character set
    #
    
    # The code being tested here is not active under ruby 1.8, and these tests
    # use features that don't exist in ruby 1.8
    if RUBY_VERSION.split('.')[0..1].join('.').to_f < 1.9
      return
    end
    
    postoutput = "This is output from\nthe post\ncommand\nwith Unicode: ol\u00E9"
    # This test depends on Ruby correct interpreting the LANG environment 
    # variable and setting an appropriate Encoding.default_external so that 
    # data captured by the output capturing process is interpreted and
    # transcoded to UTF-8 (if necessary) correctly. It seems that at the moment
    # (ruby 1.9.3-p194) ruby only correctly handles LANG set to a variant of
    # UTF-8 ("UTF-8", "en_US.UTF-8", etc.) If you sent LANG to "ISO-8859-1" or
    # "UTF-16LE" then ruby sets Encoding.default_external to "US-ASCII". Which
    # is horribly wrong. Sigh. So for now we only test UTF-8. Which means we
    # aren't actually testing transcoding. If ruby ever decides to properly
    # handle users in other locales we should expand the languages tested here.
    ['UTF-8'].each do |lang|
      testname = "output capture encoding, #{lang}"
      
      postcmd = Tempfile.new('etchoutputtest')
      postcmd.puts '#!/bin/sh'
      postcmd.print 'printf "'
      postcmd.print postoutput.encode(lang)
      postcmd.puts '"'
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
    
      oldlang = ENV['LANG']
      ENV['LANG'] = "en_US.#{lang}"
      run_etch(@server, @testroot, :testname => testname)
      ENV['LANG'] = oldlang
    
      assert_match(postoutput, latest_result_message, testname)
    end
  end
  
  def test_output_capture_timeout
    #
    # Run a test where a post command does not properly daemonize, ensure that
    # etch eventually times out.
    #
    testname = 'output capture timeout'
    
    if RUBY_VERSION.split('.')[0..1].join('.').to_f >= 1.9
      omit('This test is not normally run because the timeout is so long.')
    else
      return
    end
    
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
        run_etch(@server, @testroot, :testname => testname)
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
