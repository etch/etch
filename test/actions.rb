#!/usr/bin/ruby -w

#
# Test etch's handling of various actions:  pre, post, setup, test, etc.
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'

class EtchActionTests < Test::Unit::TestCase
  include EtchTests

  def setup
    # Generate a file to use as our etch target/destination
    @targetfile = Tempfile.new('etchtest').path
    #puts "Using #{@targetfile} as target file"
    
    # Generate a directory for our test repository
    @repodir = initialize_repository
    @port = start_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testbase = tempdir
    #puts "Using #{@testbase} as client working directory"
    
    # Generate another file to use as our link target
    @destfile = Tempfile.new('etchtest').path
    #puts "Using #{@destfile} as link destination file"
  end
  
  def test_actions

    #
    # Basic tests to ensure that actions are performed under normal
    # circumstances
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <server_setup>
            <exec>echo server_setup >> #{@repodir}/server_setup</exec>
          </server_setup>
          <setup>
            <exec>echo setup >> #{@repodir}/setup</exec>
          </setup>
          <pre>
            <exec>echo pre >> #{@repodir}/pre</exec>
          </pre>
          <file>
            <warning_file/>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <test_before_post>
            <exec>echo test_before_post >> #{@repodir}/test_before_post</exec>
          </test_before_post>
          <post>
            <exec_once>echo exec_once >> #{@repodir}/exec_once</exec_once>
            <exec_once_per_run>echo exec_once_per_run >> #{@repodir}/exec_once_per_run</exec_once_per_run>
            <exec_once_per_run>echo exec_once_per_run >> #{@repodir}/exec_once_per_run</exec_once_per_run>
            <exec>echo post >> #{@repodir}/post</exec>
          </post>
          <test>
            <exec>echo test >> #{@repodir}/test</exec>
          </test>
        </config>
      EOF
    end

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running initial action test"
    run_etch(@port, @testbase)

    # Verify that the actions were executed
    #  The server_setup action will get run several times as we loop
    #  back and forth with the server sending original sums and
    #  contents.  So just verify that it was run at least once.
    assert(get_file_contents("#{@repodir}/server_setup").include?("server_setup\n"), 'server_setup')
    assert_equal("setup\n", get_file_contents("#{@repodir}/setup"), 'setup')
    assert_equal("pre\n", get_file_contents("#{@repodir}/pre"), 'pre')
    assert_equal(
      "exec_once\n", get_file_contents("#{@repodir}/exec_once"), 'exec_once')
    assert_equal(
      "exec_once_per_run\n",
      get_file_contents("#{@repodir}/exec_once_per_run"),
      'exec_once_per_run')
    assert_equal(
      "test_before_post\n",
      get_file_contents("#{@repodir}/test_before_post"),
      'test_before_post')
    assert_equal("post\n", get_file_contents("#{@repodir}/post"), 'post')
    assert_equal("test\n", get_file_contents("#{@repodir}/test"), 'test')

    # Run etch again and make sure that the exec_once command wasn't run
    # again
    run_etch(@port, @testbase)

    assert_equal("exec_once\n", get_file_contents("#{@repodir}/exec_once"), 'exec_once_2nd_check')

    #
    # Test a failed setup command to ensure etch aborts
    #

    # Put some text into the original file so that we can make sure it
    # is not touched.
    origcontents = "This is the original text\n"
    File.delete(@targetfile)
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <setup>
            <exec>false</exec>
          </setup>
          <file>
            <warning_file/>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running initial action test"
    run_etch(@port, @testbase)

    # Verify that the file was not touched
    assert_equal(origcontents, get_file_contents(@targetfile), 'failed setup')

    #
    # Test a failed pre command to ensure etch aborts
    #

    # Put some text into the original file so that we can make sure it
    # is not touched.
    origcontents = "This is the original text\n"
    File.delete(@targetfile)
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <pre>
            <exec>false</exec>
          </pre>
          <file>
            <warning_file/>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running initial action test"
    run_etch(@port, @testbase)

    # Verify that the file was not touched
    assert_equal(origcontents, get_file_contents(@targetfile), 'failed pre')

    #
    # Run a test where the test action fails, ensure that the original
    # target file is restored and any post actions re-run afterwards
    #

    # Put some text into the original file so that we can make sure it
    # is restored.
    origcontents = "This is the original text\n"
    File.delete(@targetfile)
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <overwrite_directory/>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <exec>echo post >> #{@repodir}/post</exec>
          </post>
          <test>
            <exec>false</exec>
          </test>
        </config>
      EOF
    end

    # Change the source file so that we can see whether the original was
    # restored or not
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write("Testing a failed test\n")
    end

    # Clean up from previous runs
    File.delete("#{@repodir}/post") if File.exist?("#{@repodir}/post")

    # Run etch
    #puts "Running failed test test"
    run_etch(@port, @testbase)

    # Verify that the original was restored, and that post was run twice
    assert_equal(origcontents, get_file_contents(@targetfile), 'failed test target')
    assert_equal("post\npost\n", get_file_contents("#{@repodir}/post"), 'failed test post')

    #
    # Run a test where the test_before_post action fails, ensure that
    # post is not run
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <overwrite_directory/>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <test_before_post>
            <exec>false</exec>
          </test_before_post>
          <post>
            <exec>echo post >> #{@repodir}/post</exec>
          </post>
        </config>
      EOF
    end

    # Clean up from previous runs
    File.delete("#{@repodir}/post") if File.exist?("#{@repodir}/post")

    # Run etch
    #puts "Running failed test_before_post test"
    run_etch(@port, @testbase)

    # Verify that post was not run
    assert(!File.exist?("#{@repodir}/post"), 'failed test_before_post post')

    #
    # Run a test where the test action fails, and the original target file
    # is a symlink.  Ensure that the symlink is restored.
    #

    # Prepare the target
    File.delete(@targetfile) if File.exist?(@targetfile)
    File.symlink(@destfile, @targetfile)

    # Run etch
    #puts "Running failed test symlink test"
    run_etch(@port, @testbase)

    # Verify that the original symlink was restored
    assert_equal(@destfile, File.readlink(@targetfile), 'failed test symlink')

    #
    # Run a test where the test action fails, and the original target file
    # is a directory.  Ensure that the directory is restored.
    #

    # Prepare the target
    File.delete(@targetfile) if File.exist?(@targetfile)
    Dir.mkdir(@targetfile)
    File.open("#{@targetfile}/testfile", 'w') { |file| }

    # Run etch
    #puts "Running failed test directory test"
    run_etch(@port, @testbase)

    # Verify that the original directory was restored
    assert(File.directory?(@targetfile), 'failed test directory')
    assert(File.file?("#{@targetfile}/testfile"), 'failed test directory contents')

    #
    # Run a test where the test action fails, and there is no original
    # target file.  Ensure that the end result is that there is no file left
    # behind.
    #

    # We can reuse the config.xml from the previous test

    # Clean up from previous runs
    if File.exist?(@targetfile) || File.symlink?(@targetfile)
      FileUtils.rm_rf(@targetfile)
    end
    File.delete("#{@repodir}/post") if File.exist?("#{@repodir}/post")

    # Run etch
    #puts "Running failed test no original file test"
    run_etch(@port, @testbase)

    # Verify that the lack of an original file was restored
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), 'failed test no original file')
  end

  def teardown
    stop_server
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
    FileUtils.rm_f(@destfile)
  end
end
