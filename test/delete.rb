#!/usr/bin/ruby -w

#
# Test etch's handling of deleting files
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'

class EtchDeleteTests < Test::Unit::TestCase
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
  
  def test_delete

    #
    # Delete a file
    #
    testname = 'delete file'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <delete>
            <proceed/>
          </delete>
        </config>
      EOF
    end

    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)

    # Verify that the file was deleted
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), testname)

    #
    # Delete a link
    #
    testname = 'delete link'

    # Create the link
    File.symlink(@destfile, @targetfile)

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <delete>
            <proceed/>
          </delete>
        </config>
      EOF
    end

    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)

    # Verify that the link was deleted
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), testname)

    #
    # Delete a directory
    #
    testname = 'delete directory w/o overwrite_directory'

    # Create the directory with a file inside just to make sure the
    # delete handles that properly
    Dir.mkdir(@targetfile) if (!File.directory?(@targetfile))
    File.open("#{@targetfile}/testfile", 'w') { |file| }

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <delete>
            <proceed/>
          </delete>
        </config>
      EOF
    end

    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase, true)

    # Verify that the directory was not deleted
    assert(File.directory?(@targetfile), testname)

    #
    # Delete a directory w/ overwrite_directory
    #
    testname = 'delete directory w/ overwrite_directory'

    # Create the directory with a file inside just to make sure the
    # delete handles that properly
    Dir.mkdir(@targetfile) if (!File.directory?(@targetfile))
    File.open("#{@targetfile}/testfile", 'w') { |file| }

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <delete>
            <overwrite_directory/>
            <proceed/>
          </delete>
        </config>
      EOF
    end

    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)

    # Verify that the directory was deleted
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), testname)

    #
    # Delete a non-existent file
    #
    testname = 'delete non-existent file'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <delete>
            <proceed/>
          </delete>
        </config>
      EOF
    end

    # Run etch
    #puts "Running '#{testname}' test"
    run_etch(@port, @testbase)

    # Verify that we still don't have a file.  That's rather unlikely,
    # this is really more a test that etch doesn't throw an error if
    # told to delete something that doesn't exist, which is captured by
    # the assert within run_etch.
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), testname)

    #
    # Test duplicate script instructions
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <delete>
          <script>source</script>
          <script>source</script>
        </delete>
      </config>
      EOF
    end
    
    File.open(@targetfile, 'w') do |file|
      file.puts('Original contents')
    end

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << 'true'")
    end

    # Run etch
    #puts "Running duplicate script instructions test"
    run_etch(@port, @testbase)

    assert(!File.exist?(@targetfile), 'duplicate script instructions')

    #
    # Test contradictory script instructions
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <delete>
          <script>source</script>
          <script>source2</script>
        </delete>
      </config>
      EOF
    end

    File.open(@targetfile, 'w') do |file|
      file.puts('Original contents')
    end

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << 'true'")
    end
    File.open("#{@repodir}/source/#{@targetfile}/source2", 'w') do |file|
      file.puts("@contents << 'true'")
    end

    # Run etch
    #puts "Running contradictory script instructions test"
    run_etch(@port, @testbase, true)

    # Verify that the file wasn't removed
    assert(File.exist?(@targetfile), 'contradictory script instructions')

  end

  def teardown
    stop_server
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
    FileUtils.rm_rf(@destfile)
  end
end

