#!/usr/bin/ruby -w

#
# Test etch's handling of dependencies
#

require File.join(File.dirname(__FILE__), 'etchtest')

class EtchDependTests < Test::Unit::TestCase
  include EtchTests

  def setup
    # Generate a couple of files to use as our etch target/destinations
    @targetfile = released_tempfile
    #puts "Using #{@targetfile} as target file"
    @targetfile2 = released_tempfile
    #puts "Using #{@targetfile2} as 2nd target file"
    
    # Generate a directory for our test repository
    @repodir = initialize_repository
    @server = get_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testroot = tempdir
    #puts "Using #{@testroot} as client working directory"
  end
  
  def test_depends
    #
    # Run a basic dependency test
    #
    testname = 'initial dependency test'

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

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the files were created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'dependency file 1')
    assert_equal(sourcecontents, get_file_contents(@targetfile2), 'dependency file 2')
    # And in the right order
    assert(File.stat(@targetfile).mtime > File.stat(@targetfile2).mtime, 'dependency ordering')
  end
  
  def test_depend_request_single
    #
    # Run a dependency test where the user only requests the first
    # file on the command line
    #
    testname = 'depend with single request'
    
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

    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    File.open("#{@repodir}/source/#{@targetfile2}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(@server, @testroot, :extra_args => @targetfile, :testname => testname)

    # Verify that the files were created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'single request dependency file 1')
    assert_equal(sourcecontents, get_file_contents(@targetfile2), 'single request dependency file 2')
    # And in the right order
    assert(File.stat(@targetfile).mtime > File.stat(@targetfile2).mtime, 'single request dependency ordering')
  end
  
  def test_circular_dependency
    #
    # Run a circular dependency test
    #
    testname = 'circular dependency'

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

    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    File.open("#{@repodir}/source/#{@targetfile2}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    # Put some text into the original files so that we can make sure they
    # are not touched.
    origcontents = "This is the original text\n"
    [@targetfile, @targetfile2].each do |targetfile|
      File.delete(targetfile)
      File.open(targetfile, 'w') do |file|
        file.write(origcontents)
      end
    end
    
    run_etch(@server, @testroot, :errors_expected => true, :extra_args => @targetfile, :testname => testname)

    # Verify that the files weren't modified
    assert_equal(origcontents, get_file_contents(@targetfile), 'circular dependency file 1')
    assert_equal(origcontents, get_file_contents(@targetfile2), 'circular dependency file 2')
  end
  
  def test_command_dependency
    #
    # Test a dependency on a command
    #
    testname = 'depend on command'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <dependcommand>etchtest</dependcommand>
          <pre>
            <exec>sleep 3</exec>
          </pre>
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
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{@targetfile2}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{@targetfile2}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that the regular file and the command-generated file were created
    # properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname + ' file contents')
    assert_equal(testname, get_file_contents(@targetfile2), testname + ' command contents')
    # And verify that they were created in the right order
    assert(File.stat(@targetfile).mtime > File.stat(@targetfile2).mtime, testname + ' ordering')
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end

