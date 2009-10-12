#!/usr/bin/ruby -w

#
# Test etch's handling of creating and updating the original (orig) and
# history files
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'

class EtchHistoryTests < Test::Unit::TestCase
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
  
  def test_history
    #
    # Ensure original file is backed up and history log started
    #

    origfile = File.join(@testbase, 'orig', "#{@targetfile}.ORIG")
    historyfile = File.join(@testbase, 'history', "#{@targetfile}.HISTORY")
    historydir = File.dirname(historyfile)

    # Put some text into the original file so that we can make sure it was
    # properly backed up.
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
    #puts "Running initial history test"
    run_etch(@port, @testbase)

    assert_equal(origcontents, get_file_contents(origfile), 'original backup of file')
    system("cd #{historydir} && co -q -f -r1.1 #{historyfile}")
    #system("ls -l #{historyfile}")
    assert_equal(origcontents, get_file_contents(historyfile), 'history log started in rcs')
    system("cd #{historydir} && co -q -f #{historyfile}")
    #system("ls -l #{historyfile}")
    assert_equal(sourcecontents, get_file_contents(historyfile), 'history log of file started and updated')
    rcsexit = system("cd #{historydir} && rlog -h #{historyfile} | grep '^head: 1.2'")
    assert(rcsexit, 'history log started and updated in rcs')

    #
    # Ensure history log is updated and original file does not change
    #

    updatedsourcecontents = "This is a second test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(updatedsourcecontents)
    end

    # Run etch
    #puts "Running update test"
    run_etch(@port, @testbase)

    assert_equal(origcontents, get_file_contents(origfile), 'original backup of file unchanged')
    assert_equal(updatedsourcecontents, get_file_contents(historyfile), 'history log of file updated')
    rcsexit = system("cd #{historydir} && rlog -h #{historyfile} | grep '^head: 1.3'")
    assert(rcsexit, 'history log updated in rcs')

    #
    # Test revert feature
    #

    # Intentionally mix revert with other instructions to make sure the file
    # is reverted and nothing else happens.
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <revert/>
          <file>
            <warning_file/>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    # Run etch
    #puts "Running revert test"
    run_etch(@port, @testbase)

    assert_equal(origcontents, get_file_contents(@targetfile), 'original contents reverted')

    #
    # Update the contents of a reverted file and make sure etch doesn't
    # overwrite them, as it should no longer be managing the file.
    #

    updatedorigcontents = "This is new original text\n"
    File.open(@targetfile, 'w') do |file|
      file.write(updatedorigcontents)
    end

    # Run etch
    #puts "Running revert test"
    run_etch(@port, @testbase)

    assert_equal(updatedorigcontents, get_file_contents(@targetfile), 'Updated original contents unchanged')
  end
  
  def test_history_setup
    #
    # Use a setup command to put some contents into the target file (to
    # simulate a common usage of setup commands to install a package before
    # we backup the original file so that the original file has the default
    # config file contents) and ensure those contents are backed up as the
    # original file
    #
    
    origfile = File.join(@testbase, 'orig', "#{@targetfile}.ORIG")
    origcontents = "This is the original text"
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <setup>
            <exec>echo "#{origcontents}" > #{@targetfile}</exec>
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
    #puts "Running history setup test"
    run_etch(@port, @testbase)

    assert_equal(origcontents + "\n", get_file_contents(origfile), 'original backup of file via setup')
  end
  
  def test_delayed_history_setup
    #
    # Like the previous test this uses a setup command to put some content
    # into the target file.  However, the first run of etch is such that there
    # is no configuration for the file on this particular client, and then a
    # second run where the client is added to a node group such that the
    # configuration for the file now applies.  Ensure that the original is not
    # saved until after the file configuration applies to this host and the
    # setup command has a chance to run.
    #
    # Imagine for example that you have configuration for DNS servers in your
    # repository, which includes a setup command which installs BIND and then
    # configuration which operates on the original config file from the BIND
    # package.  You have a server that is running etch but not configured as
    # anything particular and you decide to make it a DNS server.  If etch
    # saved the original file the first time it ran on that box it would have
    # saved a NOORIG file, and then when you added the box to the dns_servers
    # node group the setup command would run, install BIND (which would create
    # the config file), but continue to report an empty original file.
    #
    testname = 'delayed history setup'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
          </file>
        </config>
      EOF
    end
    
    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)
    
    origfile = File.join(@testbase, 'orig', "#{@targetfile}.ORIG")
    origcontents = "This is the original text for #{testname}"
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <setup>
            <exec>echo "#{origcontents}" > #{@targetfile}</exec>
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
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)
    
    assert_equal(origcontents + "\n", get_file_contents(origfile), testname)
  end
  
  def test_history_link
    #
    # Ensure original file is backed up when it is a link
    #

    origfile = File.join(@testbase, 'orig', "#{@targetfile}.ORIG")
    historyfile = File.join(@testbase, 'history', "#{@targetfile}.HISTORY")
    historydir = File.dirname(historyfile)

    # Generate another file to use as our link target
    @destfile = Tempfile.new('etchtest').path

    # Make the original target a link
    File.delete(@targetfile)
    File.symlink(@destfile, @targetfile)

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
    #puts "Running history link test"
    run_etch(@port, @testbase)

    assert_equal(@destfile, File.readlink(origfile), 'original backup of link')
    system("cd #{historydir} && co -q -f -r1.1 #{historyfile}")
    assert_match("#{@targetfile} -> #{@destfile}", get_file_contents(historyfile), 'history backup of link')
  end

  def test_history_directory
    #
    # Ensure original file is backed up when it is a directory
    #

    origfile = File.join(@testbase, 'orig', "#{@targetfile}.ORIG")
    historyfile = File.join(@testbase, 'history', "#{@targetfile}.HISTORY")
    historydir = File.dirname(historyfile)

    # Make the original target a directory
    File.delete(@targetfile)
    Dir.mkdir(@targetfile)
    File.open(File.join(@targetfile, 'testfile'), 'w') { |file| }

    # Gather some stats about the file before we run etch
    before_uid = File.stat(@targetfile).uid
    before_gid = File.stat(@targetfile).gid
    before_mode = File.stat(@targetfile).mode

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    # Intentionally create the directory with different ownership and perms
    # than the original so that we can test that the original was properly
    # backed up.
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <directory>
            <owner>12345</owner>
            <group>12345</group>
            <perms>751</perms>
            <create/>
          </directory>
        </config>
      EOF
    end

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running history directory test"
    run_etch(@port, @testbase)

    assert(File.directory?(origfile), 'original backup of directory')
    # Verify that etch backed up the original directory properly
    assert_equal(before_uid, File.stat(origfile).uid, 'original directory uid')
    assert_equal(before_gid, File.stat(origfile).gid, 'original directory gid')
    assert_equal(before_mode, File.stat(origfile).mode, 'original directory mode')
    # Check that the history log looks reasonable, it should contain an
    # 'ls -ld' of the directory
    assert_match(" #{@targetfile}", get_file_contents(historyfile), 'history backup of directory')
  end

  def test_history_directory_contents
    #
    # Ensure original file is backed up when it is a directory and it is
    # being converted to something else, as the original backup is handled
    # differently in that case
    #

    #origfile = File.join(@testbase, 'orig', "#{@targetfile}.ORIG")
    origfile = File.join(@testbase, 'orig', "#{@targetfile}.TAR")
    historyfile = File.join(@testbase, 'history', "#{@targetfile}.HISTORY")
    historydir = File.dirname(historyfile)

    # Make the original target a directory
    File.delete(@targetfile)
    Dir.mkdir(@targetfile)
    File.open(File.join(@targetfile, 'testfile'), 'w') { |file| }

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
        </config>
      EOF
    end

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running history directory contents test"
    run_etch(@port, @testbase)

    # In this case, because we converted a directory to something else the
    # original will be a tarball of the directory
    assert(File.file?(origfile), 'original backup of directory converted to file')
    # The tarball should have two entries, the directory and the 'testfile'
    # we put inside it
    assert_equal('2', `tar tf #{origfile} | wc -l`.chomp.strip, 'original backup of directory contents')
  end

  def teardown
    stop_server(@pid)
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
  end
end

