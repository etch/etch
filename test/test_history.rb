#!/usr/bin/ruby -w

#
# Test etch's handling of creating and updating the original (orig) and
# history files
#

require File.expand_path('etchtest', File.dirname(__FILE__))

class EtchHistoryTests < Test::Unit::TestCase
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
    
    @origfile = File.join(@testroot, 'var', 'etch', 'orig', "#{@targetfile}.ORIG")
    @historydir = File.join(@testroot, 'var', 'etch', 'history', "#{@targetfile}.HISTORY")
  end
  
  def test_history
    #
    # Ensure original file is backed up and history log started
    #
    testname = 'initial history test'

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

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(origcontents, get_file_contents(@origfile), 'original backup of file')
    assert_equal(origcontents, get_file_contents(File.join(@historydir, '0000')), '0000 history file')
    assert_equal(sourcecontents, get_file_contents(File.join(@historydir, 'current')), 'current history file')

    #
    # Ensure history log is updated and original file does not change
    #
    testname = 'history update'

    updatedsourcecontents = "This is a second test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(updatedsourcecontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(origcontents, get_file_contents(@origfile), 'original backup of file unchanged')
    assert_equal(origcontents, get_file_contents(File.join(@historydir, '0000')), '0000 history file')
    assert_equal(sourcecontents, get_file_contents(File.join(@historydir, '0001')), '0001 history file')
    assert_equal(updatedsourcecontents, get_file_contents(File.join(@historydir, 'current')), 'updated current history file')

    #
    # Test revert feature
    #
    testname = 'revert'

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

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(origcontents, get_file_contents(@targetfile), 'original contents reverted')
    assert(!File.exist?(@origfile), 'reverted original file')
    assert_equal(origcontents, get_file_contents(File.join(@historydir, '0000')), '0000 history file')
    assert_equal(sourcecontents, get_file_contents(File.join(@historydir, '0001')), '0001 history file')
    assert_equal(updatedsourcecontents, get_file_contents(File.join(@historydir, '0002')), '0002 history file')
    assert_equal(origcontents, get_file_contents(File.join(@historydir, 'current')), 'reverted current history file')

    #
    # Update the contents of a reverted file and make sure etch doesn't
    # overwrite them, as it should no longer be managing the file.
    #
    testname = 'no update to reverted file'

    updatedorigcontents = "This is new original text\n"
    File.open(@targetfile, 'w') do |file|
      file.write(updatedorigcontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(updatedorigcontents, get_file_contents(@targetfile), 'Updated original contents unchanged')
    assert(!File.exist?(@origfile), 'reverted original file')
    assert_equal(origcontents, get_file_contents(File.join(@historydir, 'current')), 'Updated reverted current history file')
  end
  
  def test_history_setup
    #
    # Use a setup command to put some contents into the target file (to
    # simulate a common usage of setup commands to install a package before
    # we backup the original file so that the original file has the default
    # config file contents) and ensure those contents are backed up as the
    # original file.
    #
    # Generate the file contents with a script which incorporates the original
    # contents so that we also ensure that the client sends us the correct
    # contents on the first try.  We once had a bug where it took a couple of
    # tries before we achieved convergence and the client sent the correct
    # original contents.
    #
    testname = 'history setup'
    
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
              <script>source.script</script>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source.script", 'w') do |file|
      file.puts("@contents << '#{sourcecontents}'")
      file.puts("@contents << IO.read(@original_file)")
    end

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(origcontents + "\n", get_file_contents(@origfile), 'original backup of file via setup')
    assert_equal(sourcecontents + origcontents + "\n", get_file_contents(@targetfile), 'contents using original backup of file via setup')
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
    
    run_etch(@server, @testroot, :testname => 'delayed history setup, first run')
    
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
    
    run_etch(@server, @testroot, :testname => testname)
    
    assert_equal(origcontents + "\n", get_file_contents(@origfile), testname)
  end
  
  def test_history_link
    #
    # Ensure original file is backed up when it is a link
    #
    testname = 'history link'

    # Generate another file to use as our link target
    @destfile = released_tempfile

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

    run_etch(@server, @testroot, :testname => testname)

    assert_equal(@destfile, File.readlink(@origfile), 'original backup of link')
    assert_match("#{@targetfile} -> #{@destfile}", get_file_contents(File.join(@historydir, '0000')), '0000 history file of link')
  end

  def test_history_directory
    #
    # Ensure original file is backed up when it is a directory
    #
    testname = 'history directory'

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

    run_etch(@server, @testroot, :testname => testname)

    assert(File.directory?(@origfile), 'original backup of directory')
    # Verify that etch backed up the original directory properly
    assert_equal(before_uid, File.stat(@origfile).uid, 'original directory uid')
    assert_equal(before_gid, File.stat(@origfile).gid, 'original directory gid')
    assert_equal(before_mode, File.stat(@origfile).mode, 'original directory mode')
    # Check that the history log looks reasonable, it should contain an
    # 'ls -ld' of the directory
    assert_match(" #{@targetfile}", get_file_contents(File.join(@historydir, '0000')), '0000 history file of directory')
  end

  def test_history_directory_contents
    #
    # Ensure original file is backed up when it is a directory and it is
    # being converted to something else, as the original backup is handled
    # differently in that case
    #
    testname = 'history directory'

    origtarfile = File.join(@testroot, 'var', 'etch', 'orig', "#{@targetfile}.TAR")

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

    run_etch(@server, @testroot, :testname => testname)

    # In this case, because we converted a directory to something else the
    # original will be a tarball of the directory
    assert(File.file?(origtarfile), 'original backup of directory converted to file')
    # The tarball should have two entries, the directory and the 'testfile'
    # we put inside it
    assert_equal('2', `tar tf #{origtarfile} | wc -l`.chomp.strip, 'original backup of directory contents')
  end
  
  def test_history_conversion
    #
    # Test the conversion of old RCS history logs to the new format
    #
    testname = 'history conversion'
    
    # It is getting harder and harder to find a package of RCS for
    # modern operating systems.  And at this point the likelihood of
    # anyone still having unconverted history logs is getting vanishingly
    # small.  So if we don't have the RCS executables available just skip
    # these tests.
    if `which ci` == '' || `which co` == ''
      return
    end
    
    # Mock up an original file and RCS history log
    mockorigcontents = "This is the original text\n"
    FileUtils.mkdir_p(File.dirname(@origfile))
    File.open(@origfile, 'w') do |file|
      file.write(mockorigcontents)
    end
    historyparent = File.dirname(@historydir)
    FileUtils.mkdir_p(historyparent)
    File.open(@historydir, 'w') do |file|
      file.write(mockorigcontents)
    end
    histrcsdir = File.join(historyparent, 'RCS')
    FileUtils.mkdir_p(histrcsdir)
    histbase = File.basename(@historydir)
    system(
      "cd #{historyparent} && " +
      "ci -q -t-'Original of an etch modified file' " +
      "-m'Update of an etch modified file' #{histbase} && " +
      "co -q -r -kb #{histbase}")
    mocksourcecontents = "This is the contents in the RCS history log\n"
    system("cd #{historyparent} && co -q -l #{histbase}")
    File.open(@historydir, 'w') do |file|
      file.write(mocksourcecontents)
    end
    system(
      "cd #{historyparent} && " +
      "ci -q -t-'Original of an etch modified file' " +
      "-m'Update of an etch modified file' #{histbase} && " +
      "co -q -r -kb #{histbase}")
    File.open(@targetfile, 'w') do |file|
      file.write(mocksourcecontents)
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
    
    run_etch(@server, @testroot, :testname => testname)
    
    assert_equal(mockorigcontents,   get_file_contents(File.join(@historydir, '0000')), 'RCS conv 0000 history file')
    assert_equal(mocksourcecontents, get_file_contents(File.join(@historydir, '0001')), 'RCS conv 0001 history file')
    assert_equal(sourcecontents,     get_file_contents(File.join(@historydir, 'current')),  'RCS conv current history file')
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end

