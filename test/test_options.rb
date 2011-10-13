#!/usr/bin/ruby -w

#
# Test command line options to etch client
#

require File.expand_path('etchtest', File.dirname(__FILE__))
require 'webrick'

class EtchOptionTests < Test::Unit::TestCase
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
  
  def test_killswitch
    #
    # Test killswitch (not really a command-line option, but seems to
    # fit best in this file)
    #
    testname = 'killswitch'

    # Put some text into the original file so that we can make sure it is
    # not touched.
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
    
    File.open("#{@repodir}/killswitch", 'w') do |file|
      file.write('killswitch test')
    end
    
    run_etch(@server, @testroot, :errors_expected => true, :testname => testname)

    assert_equal(origcontents, get_file_contents(@targetfile), 'killswitch')
  end
  
  def test_dryrun
    #
    # Test --dry-run
    #
    testname = '--dry-run'

    # Put some text into the original file so that we can make sure it is
    # not touched.
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

    run_etch(@server, @testroot, :extra_args => '--dry-run', :testname => testname)

    assert_equal(origcontents, get_file_contents(@targetfile), '--dry-run')
  end
  
  def test_help
    output = nil
    IO.popen("#{RUBY} #{CLIENTDIR}/bin/etch --help") do |pipe|
      output = pipe.readlines
    end
    # Make sure at least something resembling help output is there
    assert(output.any? {|line| line.include?('Usage: etch')}, 'help output content')
    # Make sure it fits on the screen
    assert(output.all? {|line| line.length <= 80}, 'help output columns')
    assert(output.size <= 23, 'help output lines')
  end
  
  def test_specific_requests
    #
    # Test that the user can request specific files and commands on the
    # command line
    #
    testname = 'specific command line requests'
    
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
    targetfile2 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile2}")
    File.open("#{@repodir}/source/#{targetfile2}/config.xml", 'w') do |file|
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
    targetfile3 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile3}")
    File.open("#{@repodir}/source/#{targetfile3}/config.xml", 'w') do |file|
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
    
    sourcecontents = "Test #{testname}\n"
    [@targetfile, targetfile2, targetfile3].each do |target|
      File.open("#{@repodir}/source/#{target}/source", 'w') do |file|
        file.write(sourcecontents)
      end
    end
    
    cmdtargetfile1 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest1")
    File.open("#{@repodir}/commands/etchtest1/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{cmdtargetfile1}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{cmdtargetfile1}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    cmdtargetfile2 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest2")
    File.open("#{@repodir}/commands/etchtest2/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{cmdtargetfile2}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{cmdtargetfile2}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    cmdtargetfile3 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest3")
    File.open("#{@repodir}/commands/etchtest3/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <step>
            <guard>
              <exec>grep '#{testname}' #{cmdtargetfile3}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{cmdtargetfile3}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    # Put some text into the original files so that we can make sure the ones
    # that shouldn't get touched are not touched.
    origcontents = "This is the original text\n"
    [@targetfile, targetfile2, targetfile3, cmdtargetfile1, cmdtargetfile2, cmdtargetfile3].each do |target|
      File.open(target, 'w') do |file|
        file.write(origcontents)
      end
    end
    
    run_etch(@server, @testroot, :extra_args => "#{@targetfile} #{targetfile2} etchtest1 etchtest2", :testname => testname)
    
    # Verify that only the requested files were created
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname + ' file 1')
    assert_equal(sourcecontents, get_file_contents(targetfile2), testname + ' file 2')
    assert_equal(origcontents, get_file_contents(targetfile3), testname + ' file 3')
    # And only the requested commands were run
    assert_equal(origcontents + testname, get_file_contents(cmdtargetfile1), testname + ' cmd 1')
    assert_equal(origcontents + testname, get_file_contents(cmdtargetfile2), testname + ' cmd 2')
    assert_equal(origcontents, get_file_contents(cmdtargetfile3), testname + ' cmd 3')
  end
  
  def test_file_requests_with_depends
    #
    # Test that the user can request specific files and commands on the
    # command line with a dependency structure such that, in the right
    # circumstances, a poor implementation never completes because it
    # alternately sends/requests the orig sum for the two dependencies, never
    # sending both at the same time.
    #
    # For example, we have afile which depends on bfile and cfile.  The user
    # requests afile and bfile on the command line.  The client sends sums for
    # afile and bfile.  The server sees the need for cfile's sum, so it sends
    # back contents for bfile and a sum request for cfile and afile (since
    # afile depends on bfile).  The client sends sums for afile and cfile. 
    # The server sends back contents for cfile, and a sum request for bfile
    # and afile.  This repeats forever as the server isn't smart enough to ask
    # for everything it needs and the client isn't smart enough to send
    # everything.    
    #
    # Yup, had this bug at one point.
    #
    testname = 'command line file requests with depends'
    
    targetfile2 = released_tempfile
    targetfile3 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <depend>#{targetfile2}</depend>
          <depend>#{targetfile3}</depend>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile2}")
    File.open("#{@repodir}/source/#{targetfile2}/config.xml", 'w') do |file|
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
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile3}")
    File.open("#{@repodir}/source/#{targetfile3}/config.xml", 'w') do |file|
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
    
    sourcecontents = "Test #{testname}\n"
    [@targetfile, targetfile2, targetfile3].each do |target|
      File.open("#{@repodir}/source/#{target}/source", 'w') do |file|
        file.write(sourcecontents)
      end
    end
    
    run_etch(@server, @testroot, :extra_args => "#{@targetfile} #{targetfile2}", :testname => testname)
    
    # Verify that all were created
    assert_equal(sourcecontents, get_file_contents(@targetfile), testname + ' filesonly file 1')
    assert_equal(sourcecontents, get_file_contents(targetfile2), testname + ' filesonly file 2')
    assert_equal(sourcecontents, get_file_contents(targetfile3), testname + ' filesonly file 3')
  end
  
  def test_mixed_requests_with_depends
    #
    # Similar to previous test, but mixing file and command requests
    #
    testname = 'mixed command line requests with depends'
    
    targetfile2 = released_tempfile
    targetfile3 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <depend>#{targetfile2}</depend>
          <depend>#{targetfile3}</depend>
          <file>
            <warning_file></warning_file>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile2}")
    File.open("#{@repodir}/source/#{targetfile2}/config.xml", 'w') do |file|
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
    FileUtils.mkdir_p("#{@repodir}/source/#{targetfile3}")
    File.open("#{@repodir}/source/#{targetfile3}/config.xml", 'w') do |file|
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
    
    sourcecontents = "Test #{testname}\n"
    [@targetfile, targetfile2, targetfile3].each do |target|
      File.open("#{@repodir}/source/#{target}/source", 'w') do |file|
        file.write(sourcecontents)
      end
    end
    
    cmdtargetfile1 = released_tempfile
    FileUtils.mkdir_p("#{@repodir}/commands/etchtest1")
    File.open("#{@repodir}/commands/etchtest1/commands.xml", 'w') do |file|
      file.puts <<-EOF
        <commands>
          <dependfile>#{targetfile2}</dependfile>
          <dependfile>#{targetfile3}</dependfile>
          <step>
            <guard>
              <exec>grep '#{testname}' #{cmdtargetfile1}</exec>
            </guard>
            <command>
              <exec>printf '#{testname}' >> #{cmdtargetfile1}</exec>
            </command>
          </step>
        </commands>
      EOF
    end
    
    # Put some text into the original files.
    origcontents = "This is the original text\n"
    [@targetfile, targetfile2, targetfile3, cmdtargetfile1].each do |target|
      File.open(target, 'w') do |file|
        file.write(origcontents)
      end
    end
    
    run_etch(@server, @testroot, :extra_args => "etchtest1 #{targetfile2}", :testname => testname)
    
    # Verify that all were created
    assert_equal(origcontents + testname, get_file_contents(cmdtargetfile1), testname + ' cmdandfile cmd 1')
    assert_equal(sourcecontents, get_file_contents(targetfile2), testname + ' cmdandfile file 2')
    assert_equal(sourcecontents, get_file_contents(targetfile3), testname + ' cmdandfile file 3')
  end
  
  def test_redirects
    #
    # Test that we do not follow HTTP redirects
    #
    testname = 'do not follow redirects by default'
    
    # Put some text into the original file so that we can make sure it is
    # not touched.
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
    
    # Set up a web server which redirects to the test server
    redirect_port = 3500
    server = WEBrick::HTTPServer.new(:Port => redirect_port)
    # Trap signals to invoke the shutdown procedure cleanly
    ['INT', 'TERM'].each do |signal|
       trap(signal){ server.shutdown }
    end
    server.mount_proc("/") do |request, response|
      # Oddly request.request_uri is a URI::HTTP object, so you have to call
      # the request_uri method on it to get the actual request uri
      response.set_redirect(
        WEBrick::HTTPStatus::Found,
        URI.join("http://localhost:#{@server[:port]}/", request.request_uri.request_uri))
    end
    t = Thread.new { server.start }
    # Give webrick time to start
    sleep(5)
    
    # Test that we don't follow redirects by default
    run_etch(@server, @testroot, :errors_expected => true, :extra_args => '', :port => redirect_port, :testname => testname)
    assert_equal(origcontents, get_file_contents(@targetfile), testname)
    
    # Check that we do follow redirects with the appropriate option
    # NOTE:  Due to lack of need/demand we have not yet implemented an option
    #        to follow redirects
    # testname = 'follow redirects with --follow-redirects'
    # run_etch(@server, @testroot, :extra_args => '--follow-redirects', :port => redirect_port)
    # assert_equal(sourcecontents, get_file_contents(@targetfile), testname)
    
    # Test redirect with valid SSL
    
    # Test redirect where the first server has an invalid SSL cert but
    # redirects to a server with an valid cert
    
    # Test redirect where the first server has a valid SSL cert but
    # redirects to a server with an invalid cert
    
    # Test that we don't follow infinite redirects
    testname = 'infinite redirects'
    server.mount_proc("/") do |request, response|
      response.set_redirect(
        WEBrick::HTTPStatus::Found, "http://localhost:#{redirect_port}/")
    end
    run_etch(@server, @testroot, :errors_expected => true, :port => redirect_port, :testname => testname)
    
    server.shutdown
    t.kill
  end
  
  def test_list_files
    #
    # Test --list-files
    #
    testname = '--list-files'
    
    # Put some text into the original file so that we can make sure it is
    # not touched.
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
    
    # Test that output from etch is appropriate
    #run_etch(@server, @testroot, :extra_args => '--list-files', :testname => testname)
    output = `#{RUBY} #{CLIENTDIR}/bin/etch --generate-all --test-root=#{@testroot} --key=#{File.dirname(__FILE__)}/keys/testkey --server=http://localhost:#{@server[:port]} --list-files`
    assert(output.include?("Files under management:\n#{@targetfile}\n"))
    
    # Ensure that the target file wasn't touched
    assert_equal(origcontents, get_file_contents(@targetfile), testname)
  end
  
  def teardown
    remove_repository(@repodir)
    FileUtils.rm_rf(@testroot)
    FileUtils.rm_rf(@targetfile)
  end
end

