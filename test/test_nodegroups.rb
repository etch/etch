#!/usr/bin/ruby -w

#
# Test etch's handling of node groups and the node group hierarchy
#

require File.expand_path('etchtest', File.dirname(__FILE__))

class EtchNodeGroupTests < Test::Unit::TestCase
  include EtchTests

  def setup
    # Generate a file to use as our etch target/destination
    @targetfile = released_tempfile
    #puts "Using #{@targetfile} as target file"
    
    # Generate a directory for our test repository
    #  Specify that the node should be put into 'testgroup' in nodes.xml
    @repodir = initialize_repository(['testgroup'])
    @server = get_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testroot = tempdir
    #puts "Using #{@testroot} as client working directory"
  end
  
  def test_group
    #
    # Run a test of file creation based on a group
    #
    testname = 'basic node group'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain group="testgroup">source</plain>
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
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    #
    # Test group hierarchy
    #
    testname = 'node group hierarchy'

    File.open(File.join(@repodir, 'nodegroups.xml'), 'w') do |file|
      file.puts <<-EOF
        <nodegroups>
                <nodegroup name="testparent">
                        <child>testgroup</child>
                </nodegroup>
        </nodegroups>
      EOF
    end

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain group="testparent">source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "This is a test of group hierarchy\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    #
    # Test external grouper
    #
    testname = 'external node grouper'

    File.open(File.join(@repodir, 'nodegrouper'), 'w') do |file|
      file.puts <<-EOF
#!/bin/sh

echo "grouper_group1"
echo "grouper_group2"

      EOF
    end

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain group="grouper_group1">source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "This is a test of the external grouper\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(@server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)
    
    #
    # Test external grouper exiting with error
    #
    testname = 'external node grouper failing'

    File.open(File.join(@repodir, 'nodegrouper'), 'w') do |file|
      file.puts <<-EOF
      #!/bin/sh

      echo "grouper_group1"
      echo "grouper_group2"

      exit 1
      
      EOF
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

    oldsourcecontents = sourcecontents
    sourcecontents = "This is a test of the external grouper failing\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    # Verify that the file wasn't modified
    assert_equal(oldsourcecontents, get_file_contents(@targetfile), testname)
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end

