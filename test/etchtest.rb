#
# Module of code shared by all of the etch test cases
#

require 'test/unit'
require 'tempfile'
require 'fileutils'
require 'net/http'
require 'rbconfig'
require 'yaml'
require 'open3'

RUBY = File.join(*RbConfig::CONFIG.values_at("bindir", "ruby_install_name")) + RbConfig::CONFIG["EXEEXT"]

module EtchTests
  # Roughly ../server and ../client
  SERVERDIR = "#{File.dirname(File.dirname(File.expand_path(__FILE__)))}/server"
  CLIENTDIR = "#{File.dirname(File.dirname(File.expand_path(__FILE__)))}/client"

  # VERBOSE = :quiet
  # VERBOSE = :normal
  # VERBOSE = :debug
  VERBOSE = (ENV['VERBOSE'] || :quiet).intern

  # Creates a temporary file via Tempfile, capture the filename, tell Tempfile
  # to clean up, then return the path.  This gives the caller a filename that
  # they should be able to write to, that was recently unused and unique, and
  # that Tempfile won't try to clean up later.  This can be useful when the
  # caller might want a path to use for symlinks, directories, etc. where
  # Tempfile might choke trying to clean up what it expects to be a plain
  # file.
  def deleted_tempfile
    tmpfile = Tempfile.new('etchtest')
    tmppath = tmpfile.path
    tmpfile.close!
    tmppath
  end
  # Creates a file via Tempfile but then arranges for Tempfile to release it
  # so that the caller doesn't have to worry about Tempfile cleaning it up
  # later at an inopportune time.  It is up to the caller to ensure the file
  # is cleaned up.
  def released_tempfile
    tmppath = deleted_tempfile
    File.open(tmppath, 'w') {|file|}
    tmppath
  end
  # Haven't found a Ruby method for creating temporary directories,
  # so create a temporary file and replace it with a directory.
  def tempdir
    tmpdir = deleted_tempfile
    Dir.mkdir(tmpdir)
    tmpdir
  end

  def initialize_repository(nodegroups=[], format=:yml)
    # Generate a temp directory to put our test repository into
    repo = tempdir

    # Put the basic files into that directory needed for a basic etch tree
    # :preserve to maintain executable permissions on the scripts
    FileUtils.cp_r(Dir.glob("#{File.dirname(__FILE__)}/testrepo/*"), repo, :preserve => true)

    hostname = `facter fqdn`.chomp
    case format
    when :yml
      nodes = {}
      if nodegroups
        nodes[hostname] = nodegroups
      end
      File.open(File.join(repo, 'nodes.yml'), 'w') do |file|
        file.write nodes.to_yaml
      end
    when :xml
      nodegroups_string = ''
      nodegroups.each { |ng| nodegroups_string << "<group>#{ng}</group>\n" }
      File.open(File.join(repo, 'nodes.xml'), 'w') do |file|
        file.puts <<-EOF
        <nodes>
          <node name="#{hostname}">
            #{nodegroups_string}
          </node>
        </nodes>
        EOF
      end
    end

    puts "Created repository #{repo}" if (VERBOSE != :quiet)

    repo
  end

  def remove_repository(repo)
    FileUtils.rm_rf(repo)
  end

  @@server = nil
  def get_server(newrepo=nil)
    if !@@server
      @@server = start_server
      # FIXME: This doesn't get called for some reason, I suspect TestTask or
      # Test::Unit are interfering since they probably also use trap to
      # implement their magic.  As a result we end up leaving the server
      # running in the background.
      trap("EXIT") { stop_server(@@server) }
    end
    if newrepo
      swap_repository(@@server, newrepo)
    end
    @@server
  end

  def swap_repository(server, newrepo)
    # Point server[:repo] symlink to newrepo
    FileUtils.rm_f(server[:repo])
    File.symlink(newrepo, server[:repo])
  end

  def start_server(repo='no_repo_yet')
    # We want the running server's notion of the server base to be a symlink
    # that we can easily change later in swap_repository.
    serverbasefile = Tempfile.new('etchtest')
    serverbase = serverbasefile.path
    serverbasefile.close!
    File.symlink(repo, serverbase)
    # Pick a random port in the 3001-6000 range (range somewhat randomly chosen)
    port = 3001 + rand(3000)
    if pid = fork
      # Give the server up to 30s to start, checking every second
      catch :server_started do
        30.times do
          begin
            Net::HTTP.get 'localhost', '/', port
            throw :server_started
          rescue SystemCallError
            # retry
            sleep 1
          end
        end
        raise "Etch server failed to start"
      end
    else
      serverargs = "-p #{port} --pid #{SERVERDIR}/tmp/pids/#{port}.pid"
      case VERBOSE
      when :quiet
        serverargs += ' > /dev/null 2>&1'
      end
      with_clean_env do
        ENV['etchserverbase'] = serverbase
        exec "cd #{SERVERDIR} && #{RUBY} -S bundle exec rails server -e test #{serverargs}"
      end
    end
    {:port => port, :pid => pid, :repo => serverbase}
  end

  def stop_server(server)
    Process.kill('TERM', server[:pid])
    sleep 1
    r = Process.waitpid(server[:pid], Process::WNOHANG)
    # SIGTERM is fine for unicorn but webrick doesn't die easily
    if !r
      Process.kill('KILL', server[:pid])
      Process.waitpid(server[:pid])
    end
  end

  def assert_etch(server, testroot, options={})
    extra_args = ''
    if options[:extra_args]
      extra_args += options[:extra_args]
    end
    case VERBOSE
    when :debug
      extra_args += ' --debug'
    end

    port = server[:port]
    if options[:port]
      port = options[:port]
    end

    server = "--server=http://localhost:#{port}"
    if options[:server]
      server = options[:server]
    end

    key = "--key=#{File.dirname(__FILE__)}/keys/testkey"
    if options[:key]
      key = options[:key]
    end

    if options[:errors_expected] && VERBOSE != :quiet
      # Warn the user that errors are expected.  Otherwise it can be
      # disconcerting if you're watching the tests run and see errors.
      #sleep 3
      puts "#"
      puts "# Errors expected here"
      puts "#"
      #sleep 3
    end
    cmd = "#{RUBY} -I #{CLIENTDIR}/lib #{CLIENTDIR}/bin/etch --generate-all --test-root=#{testroot} #{server} #{key} #{extra_args}"
    Open3.popen3 cmd do |stdin, stdout, stderr, wait_thr|
      result = wait_thr.value.success?
      result = !result if options[:errors_expected]

      assert result, proc{
        "%s\nstdout: %s\nstderr: %s" % [options[:testname], stdout.readlines.join("\t"), stderr.readlines.join("\t")]
      }
    end
  end

  # Wrap File.read and return nil if an exception occurs
  def get_file_contents(file)
    # Don't follow symlinks
    if File.file?(file) && !File.symlink?(file)
      # Trap exceptions (like non-existent file) so that tests can
      # properly report back whether the file contents match or not.
      begin
        File.read(file)
      rescue
        nil
      end
    end
  end

  # Fetch the latest result for this client from the server.  Useful for
  # verifying that results were logged to the server as expected.
  def latest_result_message
    hostname = Facter['fqdn'].value
    lrm = ''
    Net::HTTP.start('localhost', @server[:port]) do |http|
      response = http.get("/results.xml?q[client_name_eq]=#{hostname}&q[s]=created_at+desc")
      if !response.kind_of?(Net::HTTPSuccess)
        response.error!
      end
      response_xml = REXML::Document.new(response.body)
      if response_xml.elements['/results/result/message']
        lrm = response_xml.elements['/results/result/message'].text
      end
    end
    lrm
  end

  def with_clean_env(&block)
    return yield unless defined? Bundler
    Bundler.with_clean_env(&block)
  end
end

