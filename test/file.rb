#!/usr/bin/ruby -w

#
# Test etch's handling of creating and updating regular files
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'

class EtchFileTests < Test::Unit::TestCase
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
  
  def test_files

    #
    # Run a test of basic file creation
    #

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

    # Run etch
    #puts "Running initial file test"
    run_etch(@port, @testbase)

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '# ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'file')

    #
    # Test with a template
    #

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

    # Run etch
    #puts "Running initial file test"
    run_etch(@port, @testbase)

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '# ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'template')

    #
    # Test using a different warning file
    #

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

    # Run etch
    #puts "Running different warning file test"
    run_etch(@port, @testbase)

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach("#{@repodir}/source/#{@targetfile}/testwarningfile") do |line|
      correctcontents << '# ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'different warning file')

    #
    # Test using no warning file
    #

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

    # Run etch
    #puts "Running no warning file test"
    run_etch(@port, @testbase)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'no warning file')

    #
    # Test using a different line comment string
    #

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

    # Run etch
    #puts "Running different line comment test"
    run_etch(@port, @testbase)

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '; ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'different line comment')

    #
    # Test using comment open/close
    #

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

    # Run etch
    #puts "Running comment open/close test"
    run_etch(@port, @testbase)

    # Verify that the file was created properly
    correctcontents = "/*\n"
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << ' * ' + line
    end
    correctcontents << " */\n"
    correctcontents << "\n"
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'comment open/close')

    #
    # Test warning on second line
    #

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

    # Run etch
    #puts "Running warning on second line test"
    run_etch(@port, @testbase)

    # Verify that the file was created properly
    correctcontents = sourcecontents_firstline
    correctcontents << "\n"
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '# ' + line
    end
    correctcontents << "\n"
    correctcontents << sourcecontents_remainder

    assert_equal(correctcontents, get_file_contents(@targetfile), 'warning on second line')

    #
    # Test no space around warning
    #

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

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running no space around warning test"
    run_etch(@port, @testbase)

    # Verify that the file was created properly
    correctcontents = ''
    IO.foreach(File.join(@repodir, 'warning.txt')) do |line|
      correctcontents << '# ' + line
    end
    correctcontents << sourcecontents

    assert_equal(correctcontents, get_file_contents(@targetfile), 'file')

    #
    # Test ownership and permissions
    #

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

    # Run etch
    #puts "Running file ownership and permissions test"
    run_etch(@port, @testbase)

    # Verify that the file ownership got set correctly
    #  Most systems don't support give-away chown, so this test won't work
    #  if not run as root
    if Process.euid == 0
      assert_equal(5000, File.lstat(@targetfile).uid, 'file uid')
      assert_equal(6000, File.lstat(@targetfile).gid, 'file gid')
    else
      warn "Not running as root, skipping file ownership test"
    end
    # Verify that the file permissions got set correctly
    perms = File.lstat(@targetfile).mode & 07777
    assert_equal(0660, perms, 'file perms')

    #
    # Test ownership w/ bogus owner/group names
    #

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

    # Run etch
    #puts "Running file ownership w/ bogus owner/group names"
    run_etch(@port, @testbase)

    # Verify that the ownership defaulted to UID/GID 0
    #  Most systems don't support give-away chown, so this test won't work
    #  if not run as root
    if Process.euid == 0
      assert_equal(0, File.lstat(@targetfile).uid, 'file uid w/ bogus owner')
      assert_equal(0, File.lstat(@targetfile).gid, 'file gid w/ bogus group')
    else
      warn "Not running as root, skipping bogus ownership test"
    end

    #
    # Run a test of always_manage_metadata
    #

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

    # Run etch
    #puts "Running always_manage_metadata test"
    run_etch(@port, @testbase)

    # Verify that the file permissions got set correctly
    perms = File.stat(@targetfile).mode & 07777
    assert_equal(0644, perms, 'always_manage_metadata perms')
  
    # And verify that the file contents didn't change
    assert_equal(testcontents, get_file_contents(@targetfile), 'always_manage_metadata contents')

    #
    # Test duplicate plain instructions
    #

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

    # Run etch
    #puts "Running duplicate plain instructions test"
    run_etch(@port, @testbase)

    # Verify that the file contents were updated
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'duplicate plain instructions')

    #
    # Test contradictory plain instructions
    #

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

    # Run etch
    #puts "Running contradictory plain instructions test"
    run_etch(@port, @testbase, true)

    # Verify that the file contents didn't change
    assert_equal(origcontents, get_file_contents(@targetfile), 'contradictory plain instructions')

    #
    # Test duplicate template instructions
    #

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

    # Run etch
    #puts "Running duplicate template instructions test"
    run_etch(@port, @testbase)

    # Verify that the file contents were updated
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'duplicate template instructions')

    #
    # Test contradictory template instructions
    #

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

    # Run etch
    #puts "Running contradictory template instructions test"
    run_etch(@port, @testbase, true)

    # Verify that the file contents didn't change
    assert_equal(origcontents, get_file_contents(@targetfile), 'contradictory template instructions')

    #
    # Test duplicate script instructions
    #

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

    # Run etch
    #puts "Running duplicate script instructions test"
    run_etch(@port, @testbase)

    # Verify that the file contents were updated
    assert_equal(sourcecontents, get_file_contents(@targetfile), 'duplicate script instructions')

    #
    # Test contradictory script instructions
    #

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

    # Run etch
    #puts "Running contradictory script instructions test"
    run_etch(@port, @testbase, true)

    # Verify that the file contents didn't change
    assert_equal(origcontents, get_file_contents(@targetfile), 'contradictory script instructions')

  end

  def teardown
    stop_server(@pid)
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
  end
end

