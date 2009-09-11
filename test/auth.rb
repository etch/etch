#!/usr/bin/ruby -w

#
# Test etch's handling of client authentication
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'
require 'net/http'
require 'rexml/document'
require 'facter'

class EtchAuthTests < Test::Unit::TestCase
  include EtchTests
  
  def setup
    # Generate a file to use as our etch target/destination
    @targetfile = Tempfile.new('etchtest').path
    #puts "Using #{@targetfile} as target file"
    
    # Generate a directory for our test repository
    @repodir = initialize_repository
    @port, @pid = start_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testbase = tempdir
    #puts "Using #{@testbase} as client working directory"
    
    # Make sure the server will initially think this is a new client
    hostname = Facter['fqdn'].value
    Net::HTTP.start('localhost', @port) do |http|
      # Find our client id
      response = http.get("/clients.xml?name=#{hostname}")
      if !response.kind_of?(Net::HTTPSuccess)
        response.error!
      end
      response_xml = REXML::Document.new(response.body)
      client_id = nil
      if response_xml.elements['/clients/client/id']
        client_id = response_xml.elements['/clients/client/id'].text
      end
      # Delete our client entry
      if client_id
        response = http.delete("/clients/#{client_id}.xml")
        if !response.kind_of?(Net::HTTPSuccess)
          response.error!
        end
      end
    end
  end
  
  # Test authentication when new clients are allowed
  def test_auth_allow_new_clients
    File.open(File.join(@repodir, 'etchserver.conf'), 'w') do |file|
      file.puts 'auth_enabled=true'
      file.puts 'auth_deny_new_clients=false'
    end
    
    #
    # New client, should work
    #
    testname = 'auth, allow new clients, new client'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
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
    
    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)
    
    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)
    
    #
    # Existing client, should work
    #
    testname = 'auth, allow new clients, existing client'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
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
    
    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)
    
    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)
    
    #
    # Existing client, bad signature, should be denied
    #
    testname = 'auth, allow new clients, existing client, bad signature'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
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
    
    # Put some text into the original file so that we can make sure it
    # is not touched.
    origcontents = "This is the original text\n"
    File.delete(@targetfile)
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    
    # Run etch with the wrong key to force a bad signature
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase, true, '--key=keys/testkey2')
    
    # Verify that the file was not touched
    assert_equal(origcontents, get_file_contents(@targetfile), testname)
  end
  # Test authentication when new clients are denied
  def test_auth_deny_new_clients
    File.open(File.join(@repodir, 'etchserver.conf'), 'w') do |file|
      file.puts 'auth_enabled=true'
      file.puts 'auth_deny_new_clients=true'
    end
    
    #
    # New client, should fail
    #
    testname = 'auth, deny new clients, new client'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
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
    
    # Put some text into the original file so that we can make sure it
    # is not touched.
    origcontents = "This is the original text\n"
    File.delete(@targetfile)
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    
    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase, true)
    
    # Verify that the file was not touched
    assert_equal(origcontents, get_file_contents(@targetfile), testname)
    
    #
    # Add this client to the server so that it will now be considered
    # an existing client
    #
    puts "# Starting a second copy of the server and adding this client to the database"
    sleep 3
    repodir2 = initialize_repository
    port2, pid2 = start_server(repodir2)
    run_etch(port2, @testbase)
    stop_server(pid2)
    remove_repository(repodir2)
    
    #
    # Existing client, should work
    #
    testname = 'auth, deny new clients, existing client'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
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
    
    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)
    
    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)
  end
  
  def teardown
    stop_server(@pid)
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
  end
end

