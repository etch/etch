#!/usr/bin/ruby -w

#
# Test command line options to etch client
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'

class EtchOptionTests < Test::Unit::TestCase
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
  end
  
  def test_killswitch
    #
    # Test killswitch (not really a command-line option, but seems to
    # fit best in this file)
    #

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end

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
    
    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    File.open("#{@repodir}/killswitch", 'w') do |file|
      file.write('killswitch test')
    end
    
    # Run etch
    #puts "Running killswitch test"
    run_etch(@port, @testbase, true)

    assert_equal(origcontents, get_file_contents(@targetfile), 'killswitch')
  end
  
  def test_dryrun
    #
    # Test --dry-run
    #

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end

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

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running --dry-run test"
    run_etch(@port, @testbase, false, '--dry-run')

    assert_equal(origcontents, get_file_contents(@targetfile), '--dry-run')
  end
  
  def test_help
    output = nil
    IO.popen("ruby ../client/etch --help") do |pipe|
      output = pipe.readlines
    end
    # Make sure at least something resembling help output is there
    assert(output.any? {|line| line.include?('Usage: etch')}, 'help output content')
    # Make sure it fits on the screen
    assert(output.all? {|line| line.length <= 80}, 'help output columns')
    assert(output.size <= 23, 'help output lines')
  end
  
  def test_specific_requests
    #
    # Test that the user can request specific files and commands on the
    # command line
    #
    testname = 'specific command line requests'
    
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
    targetfile2 = Tempfile.new('etchtest').path
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile2}")
    File.open("#{@repodir}/source/#{targetfile2}/config.xml", 'w') do |file|
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
    targetfile3 = Tempfile.new('etchtest').path
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile3}")
    File.open("#{@repodir}/source/#{targetfile3}/config.xml", 'w') do |file|
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
    [@targetfile, targetfile2, targetfile3].each do |target|
      File.open("#{@repodir}/source/#{target}/source", 'w') do |file|
        file.write(sourcecontents)
      end
    end
    
    cmdtargetfile1 = Tempfile.new('etchtest').path
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest1")
    File.open("#{@repodir}/commands/etchtest1/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{cmdtargetfile1}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{cmdtargetfile1}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    cmdtargetfile2 = Tempfile.new('etchtest').path
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest2")
    File.open("#{@repodir}/commands/etchtest2/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{cmdtargetfile2}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{cmdtargetfile2}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    cmdtargetfile3 = Tempfile.new('etchtest').path
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest3")
    File.open("#{@repodir}/commands/etchtest3/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{cmdtargetfile3}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{cmdtargetfile3}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    # Put some text into the original files so that we can make sure the ones
    # that shouldn't get touched are not touched.
    origcontents = "This is the original text\n"
    [@targetfile, targetfile2, targetfile3, cmdtargetfile1, cmdtargetfile2, cmdtargetfile3].each do |target|
      File.open(target, 'w') do |file|
        file.write(origcontents)
      end
    end
    
    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase, false, "#{@targetfile} #{targetfile2} etchtest1 etchtest2")
    
    # Verify that only the requested files were created
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname + ' file 1')
    assert_equal(sourcecontents, get_file_contents(targetfile2), testname + ' file 2')
    assert_equal(origcontents, get_file_contents(targetfile3), testname + ' file 3')
    # And only the requested commands were run
    assert_equal(origcontents + testname, get_file_contents(cmdtargetfile1), testname + ' cmd 1')
    assert_equal(origcontents + testname, get_file_contents(cmdtargetfile2), testname + ' cmd 2')
    assert_equal(origcontents, get_file_contents(cmdtargetfile3), testname + ' cmd 3')
  end
  
  def teardown
    stop_server(@pid)
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
  end
end

