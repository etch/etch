#!/usr/bin/ruby -w

#
# Test etch's handling of attribute filtering in config.xml files
#

require File.expand_path('etchtest', File.dirname(__FILE__))
require 'rubygems'  # Might be needed to find facter
require 'facter'

class EtchAttributeTests < Test::Unit::TestCase
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

  def test_group_attributes_no_entry
    #
    # Simple group name comparison with the node not in the nodes file
    #
    testname = 'node group comparison, no entry'

    repodir = initialize_repository(nil)
    server = get_server(repodir)

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.chmod(0644, @targetfile)
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end

    FileUtils.mkdir_p("#{repodir}/source/#{@targetfile}")
    File.open("#{repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
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

    sourcecontents = "Test #{testname}\n"
    File.open("#{repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(server, @testroot, :testname => testname)

    # Verify that the file was not modified
    assert_equal(origcontents, get_file_contents(@targetfile), testname)

    remove_repository(repodir)
  end

  def test_group_attributes_zero_groups
    #
    # Simple group name comparison with the node in 0 groups
    #
    testname = 'node group comparison, 0 groups'

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.chmod(0644, @targetfile)
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
              <plain group="testgroup">source</plain>
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

    # Verify that the file was not modified
    assert_equal(origcontents, get_file_contents(@targetfile), testname)

    #
    # Negate the simple group name comparison with the node in 0 groups
    #
    testname = 'negate node group comparison, 0 groups'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain group="!testgroup">source</plain>
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
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)
  end

  def test_group_attributes_one_group
    #
    # Put the node in one group for the next series of tests
    #
    repodir = initialize_repository(['testgroup'])
    server = get_server(repodir)
    
    #
    # Simple group name comparison with the node in 1 group
    #
    testname = 'node group comparison, 1 group'

    FileUtils.mkdir_p("#{repodir}/source/#{@targetfile}")
    File.open("#{repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
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

    sourcecontents = "Test #{testname}\n"
    File.open("#{repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    #
    # Negate the simple group name comparison with the node in 1 group
    #
    testname = 'negate node group comparison, 1 group'

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.chmod(0644, @targetfile)
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    
    FileUtils.mkdir_p("#{repodir}/source/#{@targetfile}")
    File.open("#{repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain group="!testgroup">source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "Test #{testname}\n"
    File.open("#{repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(server, @testroot, :testname => testname)

    # Verify that the file was not modified
    assert_equal(origcontents, get_file_contents(@targetfile), testname)
    
    #
    # Regex group name comparison with the node in 1 group
    #
    testname = 'regex node group comparison, 1 group'

    FileUtils.mkdir_p("#{repodir}/source/#{@targetfile}")
    File.open("#{repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain group="/test/">source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "Test #{testname}\n"
    File.open("#{repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    remove_repository(repodir)
  end

  def test_group_attributes_two_groups
    #
    # Put the node in two groups for the next series of tests
    #
    repodir = initialize_repository(['testgroup', 'second'])
    server = get_server(repodir)

    #
    # Simple group name comparison with the node in 2 groups
    #
    testname = 'node group comparison, 2 groups'

    FileUtils.mkdir_p("#{repodir}/source/#{@targetfile}")
    File.open("#{repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
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

    sourcecontents = "Test #{testname}\n"
    File.open("#{repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    #
    # Negate the simple group name comparison with the node in 2 groups
    #
    testname = 'negate node group comparison, 2 groups'

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.chmod(0644, @targetfile)
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end
    
    FileUtils.mkdir_p("#{repodir}/source/#{@targetfile}")
    File.open("#{repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain group="!testgroup">source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "Test #{testname}\n"
    File.open("#{repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(server, @testroot, :testname => testname)

    # Verify that the file was not modified
    assert_equal(origcontents, get_file_contents(@targetfile), testname)
    
    #
    # Regex group name comparison with the node in 2 groups
    #
    testname = 'regex node group comparison, 2 groups'

    FileUtils.mkdir_p("#{repodir}/source/#{@targetfile}")
    File.open("#{repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain group="/test/">source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "Test #{testname}\n"
    File.open("#{repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    remove_repository(repodir)
  end
  
  def test_fact_attributes
    Facter.loadfacts
    os = Facter['operatingsystem'].value
    # Facter frequently leaves extraneous whitespace on this fact, thus
    # the strip
    osrel = Facter['operatingsystemrelease'].value.strip
    
    #
    # Simple fact comparison
    #
    testname = 'fact comparison'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain operatingsystem="#{os}">source</plain>
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
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    #
    # Negate fact comparison
    #
    testname = 'negate fact comparison'

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.chmod(0644, @targetfile)
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
              <plain operatingsystem="!#{os}">source</plain>
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

    # Verify that the file was not modified
    assert_equal(origcontents, get_file_contents(@targetfile), testname)
    
    #
    # Regex fact comparison
    #
    testname = 'regex fact comparison'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain operatingsystem="/#{os[0,2]}/">source</plain>
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
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    #
    # Negate regex fact comparison
    #
    testname = 'negate regex fact comparison'

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.chmod(0644, @targetfile)
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
              <plain operatingsystem="!/#{os[0,2]}/">source</plain>
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

    # Verify that the file was not modified
    assert_equal(origcontents, get_file_contents(@targetfile), testname)

    #
    # Version fact operator comparison
    #
    testname = 'version fact operator comparison'
    
    # Try to make up a subset of operatingsystemrelease so that we really
    # test the operator functionality and not just equality.  I.e. if osrel
    # is 2.5.1 we'd like to extract 2.5
    osrelsubset = osrel
    osrelparts = osrel.split('.')
    if osrelparts.length > 1
      osrelparts.pop
      osrelsubset = osrelparts.join('.')
    end
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain operatingsystemrelease=">=#{osrelsubset}">source</plain>
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
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    #
    # Negate version fact operator comparison
    #
    testname = 'negate fact comparison'

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.chmod(0644, @targetfile)
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
              <plain operatingsystemrelease="!>=#{osrel}">source</plain>
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

    # Verify that the file was not modified
    assert_equal(origcontents, get_file_contents(@targetfile), testname)
    
    #
    # Version fact operator comparison requiring XML escape
    # The XML spec says that < and & must be escaped almost anywhere
    # outside of their use as markup.  That includes inside attribute values.
    # http://www.w3.org/TR/2006/REC-xml-20060816/#syntax
    # So if the user wants to use the < or <= operators they must escape
    # the < with &lt;
    #
    testname = 'version fact operator comparison requiring XML escape'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain operatingsystemrelease="&lt;=#{osrel}">source</plain>
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
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    #
    # Multiple fact comparison
    #
    testname = 'multiple fact comparison'

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain operatingsystem="#{os}" operatingsystemrelease="#{osrel}">source</plain>
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
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

  end
  
  def test_nodes_xml
    testname = 'node group comparison, 1 group, nodes.xml'

    repodir = initialize_repository(['testgroup'], :xml)
    server = get_server(repodir)

    FileUtils.mkdir_p("#{repodir}/source/#{@targetfile}")
    File.open("#{repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
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

    sourcecontents = "Test #{testname}\n"
    File.open("#{repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    run_etch(server, @testroot, :testname => testname)

    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)

    remove_repository(repodir)
  end

  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end
