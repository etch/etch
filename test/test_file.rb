#!/usr/bin/ruby -w

#
# Test etch's handling of creating and updating regular files
#

require File.expand_path('etchtest', File.dirname(__FILE__))

class EtchFileTests < Test::Unit::TestCase
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
  
  def test_plain
    #
    # Run a test of basic file creation
    #
    testname = 'initial file test'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
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

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '# ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'file')
  end

  def test_template
    #
    # Test with a template
    #
    testname = 'file with template'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <source>
              <template>source.template</template>
            </source>
          </file>
        </config>
      EOF
    end

    templatecontents = "This is a test\n<%= 2+2 %>\n"
    sourcecontents = "This is a test\n4\n"
    File.open("#{@repodir}/source/#{@targetfile}/source.template", 'w') do |file|
      file.write(templatecontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '# ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'template')
  end

  def test_warning
    #
    # Test using a different warning file
    #
    testname = 'different warning file'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file>testwarningfile</warning_file>
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
    warningcontents = "Warning test\nThis is a warning test\n"
    File.open("#{@repodir}/source/#{@targetfile}/testwarningfile", 'w') do |file|
      file.write(warningcontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach("#{@repodir}/source/#{@targetfile}/testwarningfile") do |line|
      correctcontents << '# ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'different warning file')
  end

  def test_no_warning
    #
    # Test using no warning file
    #
    testname = 'no warning file'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file></warning_file>
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

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'no warning file')
  end

  def test_comment_line
    #
    # Test using a different line comment string
    #
    testname = 'different line comment string'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <comment_line>; </comment_line>
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

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '; ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'different line comment')
  end

  def test_comment_open_close
    #
    # Test using comment open/close
    #
    testname = 'comment open/close'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <comment_open>/*</comment_open>
            <comment_line> * </comment_line>
            <comment_close> */</comment_close>
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

    # Verify that the file was created properly
    correctcontents = "/*\n"
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << ' * ' + line
    end
    correctcontents << " */\n"
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'comment open/close')
  end

  def test_warning_on_second_line
    #
    # Test warning on second line
    #
    testname = 'warning on second line'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_on_second_line/>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents_firstline = "This is a test\n"
    sourcecontents_remainder = "This is a second line\nAnd a third line\n"
    sourcecontents = sourcecontents_firstline + sourcecontents_remainder
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    correctcontents = sourcecontents_firstline
    correctcontents << "\n"
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '# ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents_remainder

    assert_equal(correctcontents, get_file_contents(@targetfile), 'warning on second line')
  end

  def test_no_space_around_warning
    #
    # Test no space around warning
    #
    testname = 'no space around warning'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <no_space_around_warning/>
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

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '# ' + line
    end
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'file')
  end

  def test_ownership_and_permissions
    #
    # Test ownership and permissions
    #
    testname = 'ownership and permissions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <file>
          <owner>5000</owner>
          <group>6000</group>
          <perms>0660</perms>
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

    # Verify that the file ownership got set correctly
    #  Most systems don't support give-away chown, so this test won't work
    #  if not run as root
    if Process.euid == 0
      assert_equal(5000, File.lstat(@targetfile).uid, 'file uid')
      assert_equal(6000, File.lstat(@targetfile).gid, 'file gid')
    else
      warn "Not running as root, skipping file ownership test" if (EtchTests::VERBOSE == :debug)
    end
    # Verify that the file permissions got set correctly
    perms = File.lstat(@targetfile).mode & 07777
    assert_equal(0660, perms, 'file perms')

    #
    # Test ownership w/ bogus owner/group names
    #
    testname = 'file ownership w/ bogus owner/group names'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <file>
          <owner>bogusbogusbogus</owner>
          <group>bogusbogusbogus</group>
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

    # Verify that the ownership defaulted to UID/GID 0
    #  Most systems don't support give-away chown, so this test won't work
    #  if not run as root
    if Process.euid == 0
      assert_equal(0, File.lstat(@targetfile).uid, 'file uid w/ bogus owner')
      assert_equal(0, File.lstat(@targetfile).gid, 'file gid w/ bogus group')
    else
      warn "Not running as root, skipping bogus ownership test" if (EtchTests::VERBOSE == :debug)
    end
  end
  
  def test_always_manage_metadata
    #
    # Run a test of always_manage_metadata
    #
    testname = 'always_manage_metadata'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <perms>644</perms>
            <always_manage_metadata/>
          </file>
        </config>
      EOF
    end

    testcontents = "This is a test\n"
    File.chmod(0644, @targetfile)  # Need to give ourselves write perms
    File.open(@targetfile, 'w') do |file|
      file.write(testcontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file permissions got set correctly
    perms = File.stat(@targetfile).mode & 07777
    assert_equal(0644, perms, 'always_manage_metadata perms')
  
    # And verify that the file contents didn't change
    assert_equal(testcontents, get_file_contents(@targetfile), 'always_manage_metadata contents')
  end
  
  def test_duplicate_plain
    #
    # Test duplicate plain instructions
    #
    testname = 'duplicate plain instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <file>
          <warning_file/>
          <source>
            <plain>source</plain>
            <plain>source</plain>
          </source>
        </file>
      </config>
      EOF
    end

    origcontents = "This is the original contents\n"
    File.chmod(0644, @targetfile)  # Need to give ourselves write perms
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    sourcecontents = "This is the source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file contents were updated
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'duplicate plain instructions')
  end
  
  def test_contradictory_plain
    #
    # Test contradictory plain instructions
    #
    testname = 'contradictory plain instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <file>
          <source>
            <plain>source</plain>
            <plain>source2</plain>
          </source>
        </file>
      </config>
      EOF
    end

    origcontents = "This is the original contents\n"
    File.chmod(0644, @targetfile)  # Need to give ourselves write perms
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    sourcecontents = "This is the first source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    source2contents = "This is the second source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source2", 'w') do |file|
      file.write(source2contents)
    end

    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    # Verify that the file contents didn't change
    assert_equal(origcontents, get_file_contents(@targetfile), 'contradictory plain instructions')
  end
  
  def test_duplicate_template
    #
    # Test duplicate template instructions
    #
    testname = 'duplicate template instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <file>
          <warning_file/>
          <source>
            <template>source</template>
            <template>source</template>
          </source>
        </file>
      </config>
      EOF
    end

    origcontents = "This is the original contents\n"
    File.chmod(0644, @targetfile)  # Need to give ourselves write perms
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    sourcecontents = "This is the source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file contents were updated
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'duplicate template instructions')
  end
  
  def test_contradictory_template
    #
    # Test contradictory template instructions
    #
    testname = 'contradictory template instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <file>
          <source>
            <template>source</template>
            <template>source2</template>
          </source>
        </file>
      </config>
      EOF
    end

    origcontents = "This is the original contents\n"
    File.chmod(0644, @targetfile)  # Need to give ourselves write perms
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    sourcecontents = "This is the first source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    source2contents = "This is the second source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source2", 'w') do |file|
      file.write(source2contents)
    end

    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    # Verify that the file contents didn't change
    assert_equal(origcontents, get_file_contents(@targetfile), 'contradictory template instructions')
  end
  
  def test_duplicate_script
    #
    # Test duplicate script instructions
    #
    testname = 'duplicate script instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <file>
          <warning_file/>
          <source>
            <script>source</script>
            <script>source</script>
          </source>
        </file>
      </config>
      EOF
    end

    origcontents = "This is the original contents\n"
    File.chmod(0644, @targetfile)  # Need to give ourselves write perms
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    sourcecontents = "This is the source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.puts("@contents << '#{sourcecontents}'")
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file contents were updated
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'duplicate script instructions')
  end
  
  def test_contradictory_script
    #
    # Test contradictory script instructions
    #
    testname = 'contradictory script instructions'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
      <config>
        <file>
          <source>
            <script>source</script>
            <script>source2</script>
          </source>
        </file>
      </config>
      EOF
    end

    origcontents = "This is the original contents\n"
    File.chmod(0644, @targetfile)  # Need to give ourselves write perms
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    sourcecontents = "This is the first source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    source2contents = "This is the second source contents\n"
    File.open("#{@repodir}/source/#{@targetfile}/source2", 'w') do |file|
      file.write(source2contents)
    end

    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    # Verify that the file contents didn't change
    assert_equal(origcontents, get_file_contents(@targetfile), 'contradictory script instructions')
  end
  
  def test_filename_with_special_characters
    #
    # Test filename with special characters
    #
    testname = 'filename with special characters'

    # + because urlencode and CGI.escape handle it differently, so we want to
    # catch any possible mismatches where one format is used on encode and the
    # other on decode.
    # [] because they have special meaning to the Rails parameter parsing and
    # we want to make sure that doesn't get confused.
    specialtargetfile = "#{@targetfile}+[]"
    FileUtils.mkdir_p("#{@repodir}/source/#{specialtargetfile}")
    File.open("#{@repodir}/source/#{specialtargetfile}/config.xml", 'w') do |file|
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

    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{specialtargetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(specialtargetfile), testname)
  end

  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end

