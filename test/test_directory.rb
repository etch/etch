#!/usr/bin/ruby -w

#
# Test etch's handling of creating and updating directories
#

require File.expand_path('etchtest', File.dirname(__FILE__))

class EtchDirectoryTests < Test::Unit::TestCase
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
  end

  def test_directory_create
    testname = 'directory create'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {create: true}}.to_yaml)
    end
    run_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@targetfile), testname)
  end
  def test_directory_duplicate_create
    testname = 'directory duplicate create'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {create: [true, true]}}.to_yaml)
    end
    run_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@targetfile), testname)
  end
  def test_directory_contradictory_create
    testname = 'directory contradictory create'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {create: [true, false]}}.to_yaml)
    end
    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    assert(File.file?(@targetfile), testname)
  end
  def test_directory_empty_create
    testname = 'directory empty create'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {create: [], script: 'source'}}.to_yaml)
    end

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << 'true'")
    end

    run_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@targetfile), testname)
  end
  
  def test_directory_script
    testname = 'directory script'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {script: 'source'}}.to_yaml)
    end

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << 'true'")
    end

    run_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@targetfile), testname)
  end
  def test_directory_duplicate_script
    testname = 'directory duplicate script'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {script: ['source', 'source']}}.to_yaml)
    end

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << 'true'")
    end

    run_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@targetfile), testname)
  end
  def test_directory_contradictory_script
    testname = 'directory duplicate script'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {script: ['source', 'source2']}}.to_yaml)
    end

    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << 'true'")
    end
    File.open("#{@repodir}/source/#{@targetfile}/source2", 'w') do |file|
      file.puts("@contents << 'true'")
    end

    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    assert(File.file?(@targetfile), testname)
  end
  def test_directory_empty_script
    testname = 'empty create instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {script: []}}.to_yaml)
    end

    run_etch(@server, @testroot, :testname => testname)

    assert(File.file?(@targetfile), testname)
  end
  
  def test_directory_ownership_and_permissions
    testname = 'directory ownership and perms'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.yml", 'w') do |file|
      file.write({directory: {owner: 5000, group: 6000, perms: 750, create: true}}.to_yaml)
    end
    run_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@targetfile), testname)
    # Most systems don't support give-away chown, so this test won't work
    # if not run as root
    if Process.euid == 0
      assert_equal(5000, File.lstat(@targetfile).uid, 'directory uid')
      assert_equal(6000, File.lstat(@targetfile).gid, 'directory gid')
    else
      warn "Not running as root, skipping file ownership test" if (EtchTests::VERBOSE == :debug)
    end
    perms = File.lstat(@targetfile).mode & 07777
    assert_equal(0750, perms, 'directory perms')
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end