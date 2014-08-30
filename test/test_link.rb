#!/usr/bin/ruby -w

#
# Test etch's handling of creating and updating symbolic links
#

require File.expand_path('etchtest', File.dirname(__FILE__))
require 'pathname'

class EtchLinkTests < Test::Unit::TestCase
  include EtchTests

  def setup
    # Generate a file to use as our etch target/destination
    @targetfile = released_tempfile
    #puts "Using #{@targetfile} as target file"
    
    # Delete the target file so that we're starting with nothing.  Creating
    # the target file just served to create a unique filename.
    File.delete(@targetfile)
    
    # Generate a directory for our test repository
    @repodir = initialize_repository
    @server = get_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testroot = tempdir
    #puts "Using #{@testroot} as client working directory"
    
    # Generate a couple more files to use as our link targets
    @destfile = released_tempfile
    @destfile2 = released_tempfile
    #puts "Using #{@destfile} as link destination file"
  end
  
  def test_links
    #
    # Run a test of creating a link
    #
    testname = 'initial link'

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

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile, File.readlink(@targetfile), 'link create')

    #
    # Run a test of updating the link to point to a different destination
    #
    testname = 'link update'

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

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile2, File.readlink(@targetfile), 'link update')

    #
    # Run a test of updating the link to point to a different destination,
    # this time where we start with the link pointing to a file that doesn't
    # exist.  Tests the process within etch that removes the old link before
    # we write out the updated link, in case it has problems with links to
    # files that don't exist (we had such a bug once).
    #
    testname = 'link update from non-existent file'

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

    # Remove the file that the link is currently pointing to (due to the
    # previous test)
    File.delete(@destfile2)

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile, File.readlink(@targetfile), 'link update from non-existent file')
  end
  
  def test_link_to_nonexistent_dest
    #
    # Run a test where we ask etch to create a link to a non-existent
    # destination.  It should fail by design.
    #
    testname = 'link to non-existent destination'

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

    File.delete(@destfile)

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the link was not created
    assert(!File.symlink?(@targetfile), 'link to non-existent destination')

    #
    # Then run the same test (link to non-existent destination) with the
    # override flag turned on to make sure etch does create the link.
    #
    testname = 'link to non-existent destination with override'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <link>
            <allow_nonexistent_dest/>
            <dest>#{@destfile}</dest>
          </link>
        </config>
      EOF
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the link was updated properly
    assert_equal(@destfile, File.readlink(@targetfile), 'link to non-existent destination with override')
  end
  
  def test_link_relative
    #
    # Test creating a relative link
    #
    testname = 'relative link'

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

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the link was updated properly
    assert_equal(reldestfile, File.readlink(@targetfile), 'relative link')
  end
  
  def test_link_metadata
    #
    # Test ownership and permissions
    #
    testname = 'link ownership and permissions'

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

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the link ownership got set correctly
    #  Most systems don't support give-away chown, so this test won't work
    #  if not run as root
    if Process.euid == 0
      assert_equal(5000, File.lstat(@targetfile).uid, 'link uid')
      assert_equal(6000, File.lstat(@targetfile).gid, 'link gid')
    else
      warn "Not running as root, skipping link ownership test" if (EtchTests::VERBOSE == :debug)
    end
    # Verify that the link permissions got set correctly
    perms = File.lstat(@targetfile).mode & 07777
    assert_equal(0777, perms, 'link perms')
  end
  
  def test_link_duplicate_dest
    #
    # Test duplicate dest instructions
    #
    testname = 'duplicate dest instructions'

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

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile, File.readlink(@targetfile), 'duplicate dest instructions')
  end
  
  def test_link_contradictory_dest
    #
    # Test contradictory dest instructions
    #
    testname = 'contradictory dest instructions'

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
    
    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    # Verify that the link wasn't created
    assert(!File.symlink?(@targetfile) && !File.exist?(@targetfile), 'contradictory dest instructions')
  end
  
  def test_link_empty_dest
    testname = 'empty dest instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({link: {dest: [], script: 'source'}}.to_yaml)
    end

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << '#{@destfile}'")
    end

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile, File.readlink(@targetfile), testname)
  end

  def test_link_duplicate_script
    #
    # Test duplicate script instructions
    #
    testname = 'duplicate script instructions'

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
    
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << '#{@destfile}'")
    end

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile, File.readlink(@targetfile), 'duplicate script instructions')
  end
  
  def test_link_contradictory_script
    #
    # Test contradictory script instructions
    #
    testname = 'contradictory script instructions'

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

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << '#{@destfile}'")
    end
    File.open("#{@repodir}/source/#{@targetfile}/source2", 'w') do |file|
      file.puts("@contents << '#{@destfile2}'")
    end

    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    # Verify that the link wasn't created
    assert(!File.symlink?(@targetfile) && !File.exist?(@targetfile), 'contradictory script instructions')
  end

  def test_link_empty_script
    testname = 'empty script instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({link: {script: []}}.to_yaml)
    end

    run_etch(@server, @testroot, :testname => testname)

    assert(!File.symlink?(@targetfile) && !File.exist?(@targetfile), testname)
  end

  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
    FileUtils.rm_f(@destfile)
    FileUtils.rm_f(@destfile2)
  end
end

