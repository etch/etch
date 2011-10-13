#!/usr/bin/ruby -w

#
# Test etch's handling of configuration commands
#

require File.expand_path('etchtest', File.dirname(__FILE__))

class EtchCommandTests < Test::Unit::TestCase
  include EtchTests
  
  def setup
    # Generate a file to use as a target in commands
    @targetfile = released_tempfile
    #puts "Using #{@targetfile} as target file"
    
    # Generate a directory for our test repository
    @repodir = initialize_repository
    @server = get_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testroot = tempdir
    #puts "Using #{@testroot} as client working directory"
  end
  
  def test_commands_basic
    #
    # Guard initially fails, command fixes it
    #
    testname = 'guard initially fails, command fixes it'
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{@targetfile}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that the file was created properly
    assert_equal(testname, get_file_contents(@targetfile), testname)
  end
  
  def test_commands_failure
    #
    # Guard initially fails, command doesn't fix it
    #
    testname = 'guard initially fails, command doesnt fix it'
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo '#{testname}'</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)
  end
  
  def test_commands_guard_succeeds
    #
    # Guard initially succeeds
    #
    testname = 'guard initially succeeds'
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo failure >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    File.open(@targetfile, 'w') { |file| file.print(testname) }
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that the file was not touched
    assert_equal(testname, get_file_contents(@targetfile), testname)
  end
  
  def test_commands_multiple_steps
    #
    # Multiple steps
    #
    testname = 'multiple steps'
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep firststep #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo firststep >> #{@targetfile}</exec>
            </command>
          </step>
          <step>
            <guard>
              <exec>grep secondstep #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo secondstep >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that both steps ran and in the proper order
    assert_equal("firststep\nsecondstep\n", get_file_contents(@targetfile), testname)
  end
  
  def test_commands_multiple_commands
    #
    # Multiple commands
    #
    testname = 'multiple commands'
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep firstcmd #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo firstcmd >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest2")
    File.open("#{@repodir}/commands/etchtest2/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep secondcmd #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo secondcmd >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that both commands ran, ordering doesn't matter
    assert_equal(['firstcmd', 'secondcmd'], get_file_contents(@targetfile).split("\n").sort, testname)
  end
  
  def test_commands_depend
    #
    # Multiple commands with dependency
    #
    testname = 'multiple commands with dependency'
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep firstcmd #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo firstcmd >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest2")
    File.open("#{@repodir}/commands/etchtest2/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <depend>etchtest</depend>
          <step>
            <guard>
              <exec>grep secondcmd #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo secondcmd >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that both commands ran and in the proper order
    assert_equal("firstcmd\nsecondcmd\n", get_file_contents(@targetfile), testname)
  end
  
  def test_commands_dependfile
    #
    # Command with dependency on a file
    #
    testname = 'command with file dependency'
    
    targetfile2 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile2}")
    File.open("#{@repodir}/source/#{targetfile2}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain>source</plain>
            </source>
          </file>
          <post>
            <exec>sleep 3</exec>
          </post>
        </config>
      EOF
    end
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <dependfile>#{targetfile2}</dependfile>
          <step>
            <guard>
              <exec>grep '#{testname}' #{@targetfile}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{targetfile2}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that the command-generated file and the regular file were created
    # properly
    assert_equal(testname, get_file_contents(@targetfile), testname + ' command contents')
    assert_equal(sourcecontents, get_file_contents(targetfile2), testname + ' file contents')
    # And verify that they were created in the right order
    assert(File.stat(@targetfile).mtime > File.stat(targetfile2).mtime, testname + ' ordering')
  end
  
  def test_commands_filtering
    #
    # Attribute filtering
    # Filtering of commands.xml uses the same methods as are used for the
    # filtering of config.xml, which is heavily tested.  So we just do a
    # simple test to make sure that it basically works.
    #
    testname = 'command attribute filtering'
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step group="!testgroup">
            <guard>
              <exec>grep notingroup #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo notingroup >> #{@targetfile}</exec>
            </command>
          </step>
          <step group="testgroup">
            <guard>
              <exec>grep yesingroup #{@targetfile}</exec>
            </guard>
            <command>
              <exec>echo yesingroup >> #{@targetfile}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that only the desired step executed
    assert_equal("notingroup\n", get_file_contents(@targetfile), testname)
  end
  
  def test_commands_dtd_failure
    #
    # commands.xml doesn't match DTD
    #
    testname = 'command DTD failure'
    
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest")
    File.open("#{@repodir}/commands/etchtest/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <bogus/>
          </step>
        </commands>
      EOF
    end
    
    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end

