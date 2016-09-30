#!/usr/bin/ruby -w

#
# Test transitions between various types of files (file to link, link to
# file, etc.)
#

require File.expand_path('etchtest', File.dirname(__FILE__))

class EtchTransitionTests < Test::Unit::TestCase
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

    # Generate another file to use as our link target
    @destfile = released_tempfile
  end
  
  #
  # I broke this test case into a few methods because with it all as one
  # method there was an intermittent problem where @destfile would get
  # deleted somewhere in the middle of these tests.  It was seemingly
  # very timing dependent, it would never fail when this file was run by
  # itself, only (intermittently) if this file was run via alltests.rb.
  # And adding or removing puts and system("ls -l @destfile") type calls
  # would change the failure frequency.  My gut feeling is that the
  # problem is here and not in etch itself so I added the seperate methods
  # to make the problem go away.  But I wanted to document the problem
  # here in case it crops up again in the future.
  #

  def test_file_transitions
    #
    # File to link transition
    #
    testname = 'file to link transition'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
        <link>
          <dest>#{@destfile}</dest>
        </link>
        </config>
      EOF
    end

    assert_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile, File.readlink(@targetfile), 'file to link')

    #
    # File to directory transition
    #
    testname = 'file to directory transition'

    # Reset target
    FileUtils.rm_rf(@targetfile)
    File.open(@targetfile, 'w') { |file| }

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <directory>
            <create/>
          </directory>
        </config>
      EOF
    end

    assert_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@targetfile), 'file to directory')
  end

  def test_link_transitions
    #
    # Link to file transition
    #
    testname = 'link to file transition'

    # Reset target
    FileUtils.rm_rf(@targetfile)
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

    assert_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'link to file')

    #
    # Link to file transition where the link points to a file with
    # identical contents to the file contents we should be writing out
    # (to test that the comparison method doesn't follow symlinks)
    #
    'link w/ same contents to file transition'

    # Reset target
    FileUtils.rm_rf(@targetfile)
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
    File.open(@destfile, 'w') do |file|
      file.write(sourcecontents)
    end

    assert_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'link w/ same contents to file')

    #
    # Link to directory transition
    #
    testname = 'link to directory transition'

    # Reset target
    FileUtils.rm_rf(@targetfile)
    File.symlink(@destfile, @targetfile)

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <directory>
            <create/>
          </directory>
        </config>
      EOF
    end

    assert_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@targetfile), 'link to directory')
  end

  def test_directory_transitions
    #
    # Directory to file transition
    #
    testname = 'directory to file transition'

    # Reset target
    FileUtils.rm_rf(@targetfile)
    Dir.mkdir(@targetfile)

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

    assert_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'directory to file')

    #
    # Directory to link transition
    #
    testname = 'directory to link transition'

    # Reset target
    FileUtils.rm_rf(@targetfile)
    Dir.mkdir(@targetfile)

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
        <link>
          <overwrite_directory/>
          <dest>#{@destfile}</dest>
        </link>
        </config>
      EOF
    end

    assert_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile, File.readlink(@targetfile), 'directory to link')
  end

  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
    FileUtils.rm_f(@destfile)
  end
end

