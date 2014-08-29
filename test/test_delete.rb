#!/usr/bin/ruby -w

#
# Test etch's handling of deleting files
#

require File.expand_path('etchtest', File.dirname(__FILE__))

class EtchDeleteTests < Test::Unit::TestCase
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
    #puts "Using #{@destfile} as link destination file"
  end
  
  def test_delete_file
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

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file was deleted
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), testname)
  end

  def test_delete_link
    #
    # Delete a link
    #
    testname = 'delete link'

    # Create the link
    FileUtils.rm_f(@targetfile)
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

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the link was deleted
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), testname)
  end
  
  def test_delete_directory
    #
    # Delete a directory
    #
    testname = 'delete directory w/o overwrite_directory'

    # Create the directory with a file inside just to make sure the
    # delete handles that properly
    FileUtils.rm_f(@targetfile)
    Dir.mkdir(@targetfile)
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

    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    # Verify that the directory was not deleted
    assert(File.directory?(@targetfile), testname)
  end
  
  def test_delete_overwrite_directory
    #
    # Delete a directory w/ overwrite_directory
    #
    testname = 'delete directory w/ overwrite_directory'

    # Create the directory with a file inside just to make sure the
    # delete handles that properly
    FileUtils.rm_f(@targetfile)
    Dir.mkdir(@targetfile)
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

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the directory was deleted
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), testname)
  end
  
  def test_delete_nonexistent
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

    run_etch(@server, @testroot, :testname => testname)

    # Verify that we still don't have a file.  That's rather unlikely,
    # this is really more a test that etch doesn't throw an error if
    # told to delete something that doesn't exist, which is captured by
    # the assert within run_etch.
    assert(!File.exist?(@targetfile) && !File.symlink?(@targetfile), testname)
  end
  
  def test_delete_duplicate_script
    #
    # Test duplicate script instructions
    #
    testname = 'duplicate script'

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

    run_etch(@server, @testroot, :testname => testname)

    assert(!File.exist?(@targetfile), testname)
  end
  
  def test_delete_contradictory_script
    #
    # Test contradictory script instructions
    #
    testname = 'contradictory script'

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

    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    # Verify that the file wasn't removed
    assert(File.exist?(@targetfile), testname)
  end

  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
    FileUtils.rm_rf(@destfile)
  end
end

