#!/usr/bin/ruby -w

#
# Test etch's handling of dependencies
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'

class EtchDependTests < Test::Unit::TestCase
  include EtchTests

  def setup
    # Generate a couple of files to use as our etch target/destinations
    @targetfile = Tempfile.new('etchtest').path
    #puts "Using #{@targetfile} as target file"
    @targetfile2 = Tempfile.new('etchtest').path
    #puts "Using #{@targetfile2} as 2nd target file"
    
    # Generate a directory for our test repository
    @repodir = initialize_repository
    @port = start_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testbase = tempdir
    #puts "Using #{@testbase} as client working directory"
  end
  
  def test_depends

    #
    # Run a basic dependency test
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <depend>#{@targetfile2}</depend>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <!-- Pause so we can verify that etch processed these in the right order -->
            <exec>sleep 3</exec>
          </post>
        </config>
      EOF
    end
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile2}")
    File.open("#{@repodir}/source/#{@targetfile2}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <!-- Pause so we can verify that etch processed these in the right order -->
            <exec>sleep 3</exec>
          </post>
        </config>
      EOF
    end

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    File.open("#{@repodir}/source/#{@targetfile2}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running initial dependency test"
    run_etch(@port, @testbase, '--debug')

    # Verify that the files were created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'dependency file 1')
    assert_equal(sourcecontents, get_file_contents(@targetfile2), 'dependency file 2')
    # And in the right order
    assert(File.stat(@targetfile).mtime > File.stat(@targetfile2).mtime, 'dependency ordering')

    #
    # Run a dependency test where the user only requests the first
    # file on the command line
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <depend>#{@targetfile2}</depend>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <!-- Pause so we can verify that etch processed these in the right order -->
            <exec>sleep 3</exec>
          </post>
        </config>
      EOF
    end
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile2}")
    File.open("#{@repodir}/source/#{@targetfile2}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <!-- Pause so we can verify that etch processed these in the right order -->
            <exec>sleep 3</exec>
          </post>
        </config>
      EOF
    end

    # Vary the source contents so we know the files were updated
    sourcecontents = "This is a different test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    File.open("#{@repodir}/source/#{@targetfile2}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running single request dependency test"
    run_etch(@port, @testbase, @targetfile)

    # Verify that the files were created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'single request dependency file 1')
    assert_equal(sourcecontents, get_file_contents(@targetfile2), 'single request dependency file 2')
    # And in the right order
    assert(File.stat(@targetfile).mtime > File.stat(@targetfile2).mtime, 'single request dependency ordering')

    #
    # Run a circular dependency test
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <depend>#{@targetfile2}</depend>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile2}")
    File.open("#{@repodir}/source/#{@targetfile2}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <depend>#{@targetfile}</depend>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    # Vary the source contents so we know the files weren't updated
    oldsourcecontents = sourcecontents
    sourcecontents = "This is a circular dependency test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    File.open("#{@repodir}/source/#{@targetfile2}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running circular test"
    sleep 3
    puts "#"
    puts "# Errors expected here"
    puts "#"
    sleep 3
    run_etch(@port, @testbase, @targetfile)

    # Verify that the files weren't modified
    assert_equal(oldsourcecontents, get_file_contents(@targetfile), 'circular dependency file 1')
    assert_equal(oldsourcecontents, get_file_contents(@targetfile2), 'circular dependency file 2')

  end

  def teardown
    stop_server
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
  end
end

