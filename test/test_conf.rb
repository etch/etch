#!/usr/bin/ruby -w

#
# Test etch's handling of its configuration file, etch.conf
#

require File.join(File.dirname(__FILE__), 'etchtest')

class EtchConfTests < Test::Unit::TestCase
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
  
  def test_conf_server
    #
    # Test the server setting in etch.conf
    #
    testname = 'etch.conf server setting'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    # Test that it fails with a bogus etch.conf server setting
    Dir.mkdir("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "server = http://bogushost:0"
    end
    
    # The --server option normally used by run_etch will override the config
    # file, signal run_etch to leave out the --server option
    run_etch(@server, @testroot, :server => '', :errors_expected => true)
    
    # And confirm that it now succeeds with a correct etch.conf server setting
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "server = http://localhost:#{@server[:port]}"
    end
    
    # The --server option normally used by run_etch will override the config
    # file, signal run_etch to leave out the --server option
    run_etch(@server, @testroot, :server => '')
    assert_equal(sourcecontents, get_file_contents(@targetfile))
  end
  
  def test_conf_local
    #
    # Test the local setting in etch.conf
    #
    testname = 'etch.conf local setting'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    # Test that it fails with a bogus etch.conf local setting
    Dir.mkdir("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "local = /not/a/valid/path"
    end
    
    # Although the config file local setting will override it, tell run_etch
    # to leave out the --server option to avoid confusion
    run_etch(@server, @testroot, :server => '', :errors_expected => true)
    
    # And confirm that it now succeeds with a correct etch.conf local setting
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "local = #{@repodir}"
    end
    
    # Although the config file local setting will override it, tell run_etch
    # to leave out the --server option to avoid confusion
    run_etch(@server, @testroot, :server => '')
    assert_equal(sourcecontents, get_file_contents(@targetfile))
  end
  
  def test_conf_key
    # FIXME
    
    # The --key option normally used by run_etch will override the config
    # file, signal run_etch to leave out the --key option
    #run_etch(@server, @testroot, :key => '')
  end
  
  def test_conf_path
    #
    # Test the path setting in etch.conf
    #
    testname = 'etch.conf path setting'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <exec>testpost</exec>
          </post>
        </config>
      EOF
    end
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    Dir.mkdir("#{@repodir}/pathtest")
    File.open("#{@repodir}/pathtest/testpost", 'w') do |file|
      file.puts '#!/bin/sh'
      file.puts "touch #{@repodir}/pathtest/testpost.output"
    end
    File.chmod(0755, "#{@repodir}/pathtest/testpost")
    
    # Test that it fails without an etch.conf path setting
    run_etch(@server, @testroot)
    assert(!File.exist?("#{@repodir}/pathtest/testpost.output"))
    
    Dir.mkdir("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "path = /bin:/usr/bin:/sbin:/usr/sbin:#{@repodir}/pathtest"
    end
    
    # And confirm that it now succeeds with an etch.conf path setting
    run_etch(@server, @testroot)
    assert(File.exist?("#{@repodir}/pathtest/testpost.output"))
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end
