#!/usr/bin/ruby -w

#
# Test etch's handling of local requests
#

require "./#{File.dirname(__FILE__)}/etchtest"

class EtchLocalRequestsTests < Test::Unit::TestCase
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
  
  def test_local_requests_script
    #
    # Run a test with a local request and a script
    #
    testname = 'local request with script'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <script>source.script</script>
            </source>
          </file>
        </config>
      EOF
    end
    
    # Create the local request file
    requestdir = File.join(@testroot, 'var', 'etch', 'requests', @targetfile)
    requestfile = File.join(requestdir, 'testrequest')
    FileUtils.mkdir_p(requestdir)
    File.open(requestfile, 'w') do |file|
      file.puts <<-EOF
        <request>
          <foo/>
        </request>
      EOF
    end
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source.script", 'w') do |file|
      file.puts <<-EOF
        require 'rexml/document'
        doc = REXML::Document.new(@local_requests)
        if doc.root.elements['/requests/request/foo']
          @contents << '#{sourcecontents}'
        end
      EOF
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that the file was created properly
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname)
  end
  
  def test_local_requests_template
    #
    # Run a test with a local request and a template
    #
    testname = 'local request with template'
    
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <template>source.template</template>
            </source>
          </file>
        </config>
      EOF
    end
    
    # Create the local request file
    requestdir = File.join(@testroot, 'var', 'etch', 'requests', @targetfile)
    requestfile = File.join(requestdir, 'testrequest')
    FileUtils.mkdir_p(requestdir)
    File.open(requestfile, 'w') do |file|
      file.puts <<-EOF
        <request>
          <foo/>
        </request>
      EOF
    end
    
    sourcecontents = "Test #{testname}\n"
    File.open("#{@repodir}/source/#{@targetfile}/source.template", 'w') do |file|
      file.puts <<-EOF
        <% sourcecontents = '#{sourcecontents}' %>
        <% require 'rexml/document' %>
        <% doc = REXML::Document.new(@local_requests) %>
        <% if doc.root.elements['/requests/request/foo'] %>
          <%= sourcecontents %>
        <% end %>
      EOF
    end
    
    run_etch(@server, @testroot, :testname => testname)
    
    # Verify that the file was created properly
    # Our whitespace in the heredoc above gets added to the generated file, so
    # pass both strings through strip so we just compare the meat at the
    # center.
    assert_equal(sourcecontents.strip, get_file_contents(@targetfile).strip, testname)
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end

