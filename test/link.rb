#!/usr/bin/ruby -w

#
# Test etch's handling of creating and updating symbolic links
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'
require 'pathname'

class EtchLinkTests < Test::Unit::TestCase
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
    
    # Generate a couple more files to use as our link targets
    @destfile = Tempfile.new('etchtest').path
    @destfile2 = Tempfile.new('etchtest').path
    #puts "Using #{@destfile} as link destination file"
  end
  
  def test_links
    #
    # Run a test of creating a link
    #

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

    # Delete the target file so that we're starting with nothing.  Creating
    # the target file just served to create a unique filename.
    File.delete(@targetfile)

    # Run etch
    #puts "Running initial link test"
    run_etch(@port, @testbase)

    assert_equal(@destfile, File.readlink(@targetfile), 'link create')

    #
    # Run a test of updating the link to point to a different destination
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <link>
            <dest>#{@destfile2}</dest>
          </link>
        </config>
      EOF
    end

    # Run etch
    #puts "Running link update test"
    run_etch(@port, @testbase)

    assert_equal(@destfile2, File.readlink(@targetfile), 'link update')

    #
    # Run a test of updating the link to point to a different destination,
    # this time where we start with the link pointing to a file that doesn't
    # exist.  Tests the process within etch that removes the old link before
    # we write out the updated link, in case it has problems with links to
    # files that don't exist (we had such a bug once).
    #

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

    # Remove the file that the link is currently pointing to
    File.delete(@destfile2)

    # Run etch
    #puts "Running link update from non-existent file test"
    run_etch(@port, @testbase)

    assert_equal(@destfile, File.readlink(@targetfile), 'link update from non-existent file')

    #
    # Run a test where we ask etch to create a link to a non-existent
    # destination.  It should fail by design.
    #

    # We removed @destfile2 in the previous test, so that will work for our
    # test destination

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <link>
            <dest>#{@destfile2}</dest>
          </link>
        </config>
      EOF
    end

    # Run etch
    #puts "Running link to non-existent destination test"
    run_etch(@port, @testbase)

    # Verify that the link was not updated, it should still point to
    # @destfile
    assert_equal(@destfile, File.readlink(@targetfile), 'link to non-existent destination')

    #
    # Then run the same test (link to non-existent destination) with the
    # override flag turned on to make sure etch does create the link.
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <link>
            <allow_nonexistent_dest/>
            <dest>#{@destfile2}</dest>
          </link>
        </config>
      EOF
    end

    # Run etch
    #puts "Running link to non-existent destination with override test"
    run_etch(@port, @testbase)

    # Verify that the link was updated properly
    assert_equal(@destfile2, File.readlink(@targetfile), 'link to non-existent destination with override')

    #
    # Test creating a relative link
    #

    # We'll use @destfile as the target, but need a relative path to it.
    # Conveniently Pathname has a function to figure that out for us.
    targetdir = File.dirname(@targetfile)
    reldestfile = Pathname.new(@destfile).relative_path_from(Pathname.new(targetdir)).to_s

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <link>
            <dest>#{reldestfile}</dest>
          </link>
        </config>
      EOF
    end

    # Run etch
    #puts "Running relative link test"
    run_etch(@port, @testbase)

    # Verify that the link was updated properly
    assert_equal(reldestfile, File.readlink(@targetfile), 'relative link')

    #
    # Test ownership and permissions
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <link>
            <owner>5000</owner>
            <group>6000</group>
            <perms>0777</perms>
            <dest>#{@destfile}</dest>
          </link>
        </config>
      EOF
    end

    # Run etch
    #puts "Running link ownership and permissions test"
    run_etch(@port, @testbase)

    # Verify that the link ownership got set correctly
    #  Most systems don't support give-away chown, so this test won't work
    #  if not run as root
    if Process.euid == 0
      assert_equal(5000, File.lstat(@targetfile).uid, 'link uid')
      assert_equal(6000, File.lstat(@targetfile).gid, 'link gid')
    else
      warn "Not running as root, skipping link ownership test"
    end
    # Verify that the link permissions got set correctly
    perms = File.lstat(@targetfile).mode & 07777
    assert_equal(0777, perms, 'link perms')
    
    #
    # Test duplicate dest instructions
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <link>
          <dest>#{@destfile}</dest>
          <dest>#{@destfile}</dest>
        </link>
      </config>
      EOF
    end

    File.delete(@targetfile)

    # Run etch
    #puts "Running duplicate dest instructions test"
    run_etch(@port, @testbase)

    assert_equal(@destfile, File.readlink(@targetfile), 'duplicate dest instructions')

    #
    # Test contradictory dest instructions
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <link>
          <dest>#{@destfile}</dest>
          <dest>#{@destfile2}</dest>
        </link>
      </config>
      EOF
    end

    File.delete(@targetfile) if File.symlink?(@targetfile)

    # Run etch
    #puts "Running contradictory dest instructions test"
    run_etch(@port, @testbase, true)

    # Verify that the link wasn't created
    assert(!File.symlink?(@targetfile) && !File.exist?(@targetfile), 'contradictory dest instructions')

    #
    # Test duplicate script instructions
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <link>
          <script>source</script>
          <script>source</script>
        </link>
      </config>
      EOF
    end
    
    File.delete(@targetfile) if File.symlink?(@targetfile)

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << '#{@destfile}'")
    end

    # Run etch
    #puts "Running duplicate script instructions test"
    run_etch(@port, @testbase)

    assert_equal(@destfile, File.readlink(@targetfile), 'duplicate script instructions')

    #
    # Test contradictory script instructions
    #

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <link>
          <script>source</script>
          <script>source2</script>
        </link>
      </config>
      EOF
    end

    File.delete(@targetfile) if File.symlink?(@targetfile)

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << '#{@destfile}'")
    end
    File.open("#{@repodir}/source/#{@targetfile}/source2", 'w') do |file|
      file.puts("@contents << '#{@destfile2}'")
    end

    # Run etch
    #puts "Running contradictory script instructions test"
    run_etch(@port, @testbase, true)

    # Verify that the link wasn't created
    assert(!File.symlink?(@targetfile) && !File.exist?(@targetfile), 'contradictory script instructions')

  end

  def teardown
    stop_server
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
    FileUtils.rm_f(@destfile)
    FileUtils.rm_f(@destfile2)
  end
end

