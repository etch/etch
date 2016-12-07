#!/usr/bin/ruby -w

#
# Test etch's handling of its configuration file, etch.conf
#

require File.expand_path('etchtest', File.dirname(__FILE__))
require 'net/http'
require 'rexml/document'
require 'cgi'
begin
  # Try loading facter w/o gems first so that we don't introduce a
  # dependency on gems if it is not needed.
  require 'facter'
rescue LoadError
  require 'rubygems'
  require 'facter'
end

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
    
    testname = 'etch.conf server setting'
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    # Test that it fails with a bogus etch.conf server setting
    testname = 'etch.conf server setting, bogus'
    Dir.mkdir("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "server = http://bogushost:0"
    end
    
    # The --server option normally used by assert_etch will override the config
    # file, signal assert_etch to leave out the --server option
    assert_etch(@server, @testroot, :server => '', :errors_expected => true, :testname => testname)
    
    # And confirm that it now succeeds with a correct etch.conf server setting
    testname = 'etch.conf server setting, correct'
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "server = http://localhost:#{@server[:port]}"
    end
    
    # The --server option normally used by assert_etch will override the config
    # file, signal assert_etch to leave out the --server option
    assert_etch(@server, @testroot, :server => '', :testname => testname)
    assert_equal(sourcecontents, get_file_contents(@targetfile))
  end
  
  def test_conf_local
    #
    # Test the local setting in etch.conf
    #
    
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
    
    testname = 'etch.conf local setting'
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    # Test that it fails with a bogus etch.conf local setting
    testname = 'etch.conf local setting, bogus'
    Dir.mkdir("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "local = /not/a/valid/path"
    end
    
    # Although the config file local setting will override it, tell assert_etch
    # to leave out the --server option to avoid confusion
    assert_etch(@server, @testroot, :server => '', :errors_expected => true, :testname => testname)
    
    # And confirm that it now succeeds with a correct etch.conf local setting
    testname = 'etch.conf local setting, correct'
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "local = #{@repodir}"
    end
    
    # Although the config file local setting will override it, tell assert_etch
    # to leave out the --server option to avoid confusion
    assert_etch(@server, @testroot, :server => '', :testname => testname)
    assert_equal(sourcecontents, get_file_contents(@targetfile))
  end
  
  def test_conf_key
    # Start a server instance that has authentication enabled
    authrepodir = initialize_repository
    File.open(File.join(authrepodir, 'etchserver.conf'), 'w') do |file|
      file.puts 'auth_enabled=true'
      file.puts 'auth_deny_new_clients=true'
    end
    
    # These tests set an etchserver.conf.  The server only reads that file
    # once and caches the settings, so we need to start up new server
    # instances for these tests rather than reusing the global test server.
    authserver = start_server(authrepodir)
    
    # Generate an SSH key pair
    keyfile = Tempfile.new('etchtest')
    File.unlink(keyfile.path)
    system("ssh-keygen -t rsa -f #{keyfile.path} -N '' -q")
    pubkeycontents = File.read("#{keyfile.path}.pub")
    sshrsakey = pubkeycontents.chomp.split[1]
    
    # Set the client's key fact on the server to this new key
    hostname = Facter['fqdn'].value
    # Note the use of @server instead of authserver, we need to talk to
    # a server that doesn't have authentication enabled in order to make
    # these changes.
    Net::HTTP.start('localhost', @server[:port]) do |http|
      # Find our client id
      response = http.get("/clients.xml?q[name_eq]=#{hostname}")
      if !response.kind_of?(Net::HTTPSuccess)
        response.error!
      end
      response_xml = REXML::Document.new(response.body)
      client_id = nil
      if response_xml.elements['/clients/client/id']
        client_id = response_xml.elements['/clients/client/id'].text
        # If there's an existing "sshrsakey" fact for this client then
        # delete it
        response = http.get("/facts.xml?q[client_id_eq]=#{client_id}&" +
          "q[key_eq]=sshrsakey")
        if !response.kind_of?(Net::HTTPSuccess)
          response.error!
        end
        response_xml = REXML::Document.new(response.body)
        fact_id = nil
        if response_xml.elements['/facts/fact/id']
          fact_id = response_xml.elements['/facts/fact/id'].text
        end
        if fact_id
          response = http.delete("/facts/#{fact_id}.xml")
          if !response.kind_of?(Net::HTTPSuccess)
            response.error!
          end
        end
      else
        # Handle the case where this is the first test this client has
        # ever run and as such there's no entry for the client in the
        # database.
        response = http.post('/clients.xml',
          "client[name]=#{CGI.escape(hostname)}")
        if !response.kind_of?(Net::HTTPSuccess)
          response.error!
        end
        response_xml = REXML::Document.new(response.body)
        client_id = response_xml.elements['/client/id'].text
      end
      # Insert our key as the client's "sshrsakey" fact
      response = http.post('/facts.xml',
        "fact[client_id]=#{client_id}&" +
        "fact[key]=sshrsakey&" +
        "fact[value]=#{CGI.escape(sshrsakey)}")
      if !response.kind_of?(Net::HTTPSuccess)
        response.error!
      end
    end
    
    FileUtils.mkdir_p("#{authrepodir}/source/#{@targetfile}")
    File.open("#{authrepodir}/source/#{@targetfile}/config.xml", 'w') do |file|
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
    
    testname = 'etch.conf key setting'
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{authrepodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    # Test that it fails with a bogus etch.conf key setting
    testname = 'etch.conf key setting, bogus'
    Dir.mkdir("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "key = /not/a/valid/path"
    end
    
    # The --key option normally used by assert_etch will override the config
    # file, signal assert_etch to leave out the --key option
    assert_etch(authserver, @testroot, :key => '',
             :errors_expected => true, :testname => testname)
    
    # And confirm that it now succeeds with a correct etch.conf key setting
    testname = 'etch.conf key setting, correct'
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "key = #{keyfile.path}"
    end
    
    # The --key option normally used by assert_etch will override the config
    # file, signal assert_etch to leave out the --key option
    assert_etch(authserver, @testroot, :key => '', :testname => testname)
    assert_equal(sourcecontents, get_file_contents(@targetfile))
    
    # Tempfile will clean up the private key file, but not the associated
    # public key file
    FileUtils.rm_rf("#{keyfile.path}.pub")
  end
  
  def test_conf_path
    #
    # Test the path setting in etch.conf
    #
    
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
    
    testname = 'etch.conf path setting'
    
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
    testname = 'etch.conf path setting, not set'
    assert_etch(@server, @testroot, :testname => testname)
    assert(!File.exist?("#{@repodir}/pathtest/testpost.output"))
    
    testname = 'etch.conf path setting, set'
    Dir.mkdir("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "path = /bin:/usr/bin:/sbin:/usr/sbin:#{@repodir}/pathtest"
    end
    
    # And confirm that it now succeeds with an etch.conf path setting
    assert_etch(@server, @testroot, :testname => testname)
    assert(File.exist?("#{@repodir}/pathtest/testpost.output"))
  end
  
  def test_conf_detailed_results
    #
    # Test the detailed_results setting in etch.conf
    #
    
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
    
    # No setting, should log to server by default
    testname = 'etch.conf detailed_results setting, not set'
    # We add a random component to the contents so that we can distinguish
    # our test run from others in the server database
    sourcecontents = "Test #{testname}, #{rand}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    assert_etch(@server, @testroot, :testname => testname)
    assert_match(sourcecontents, latest_result_message, testname)
    
    # Configure logging to server
    testname = 'etch.conf detailed_results setting, log to server'
    # We add a random component to the contents so that we can distinguish
    # our test run from others in the server database
    sourcecontents = "Test #{testname}, #{rand}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    FileUtils.mkdir_p("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "detailed_results = SERVER"
    end
    assert_etch(@server, @testroot, :testname => testname)
    assert_match(sourcecontents, latest_result_message, testname)
    
    # Configure logging to file
    logfile = Tempfile.new('etchlog')
    testname = 'etch.conf detailed_results setting, log to file'
    sourcecontents = "Test #{testname}, #{rand}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    FileUtils.mkdir_p("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "detailed_results = #{logfile.path}"
    end
    assert_etch(@server, @testroot, :testname => testname)
    assert_match(sourcecontents, File.read(logfile.path), testname)
    # Check that details weren't sent to server
    # Odd that assert_no_match requires a Regexp when assert_match accepts a String
    assert_no_match(Regexp.new(Regexp.escape(sourcecontents)), latest_result_message, testname)
    
    # Configure logging to server and file
    logfile = Tempfile.new('etchlog')
    testname = 'etch.conf detailed_results setting, log to server and file'
    # We add a random component to the contents so that we can distinguish
    # our test run from others in the server database
    sourcecontents = "Test #{testname}, #{rand}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    FileUtils.mkdir_p("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "detailed_results = SERVER"
      file.puts "detailed_results = #{logfile.path}"
    end
    assert_etch(@server, @testroot, :testname => testname)
    assert_match(sourcecontents, latest_result_message, testname)
    assert_match(sourcecontents, File.read(logfile.path), testname)
    
    # Configure no logging
    testname = 'etch.conf detailed_results setting, log nowhere'
    sourcecontents = "Test #{testname}, #{rand}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    FileUtils.mkdir_p("#{@testroot}/etc")
    File.open("#{@testroot}/etc/etch.conf", 'w') do |file|
      file.puts "detailed_results ="
    end
    assert_etch(@server, @testroot, :testname => testname)
    # Check that details weren't sent to server
    # Odd that assert_no_match requires a Regexp when assert_match accepts a String
    assert_no_match(Regexp.new(Regexp.escape(sourcecontents)), latest_result_message, testname)
    
    # FIXME: verify no logging in dry run mode
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end
