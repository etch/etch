#
# Module of code shared by all of the etch test cases
#

require 'test/unit'
require 'tempfile'
require 'fileutils'
require 'net/http'
require 'rbconfig'

RUBY = File.join(*RbConfig::CONFIG.values_at("bindir", "ruby_install_name")) + RbConfig::CONFIG["EXEEXT"]

module EtchTests
  # Roughly ../server and ../client
  SERVERDIR = "#{File.dirname(File.dirname(File.expand_path(__FILE__)))}/server"
  CLIENTDIR = "#{File.dirname(File.dirname(File.expand_path(__FILE__)))}/client"
  
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
  
  def initialize_repository(nodegroups=[])
    # Generate a temp directory to put our test repository into
    repo = tempdir
    
    # Put the basic files into that directory needed for a basic etch tree
    # :preserve to maintain executable permissions on the scripts
    FileUtils.cp_r(Dir.glob("#{File.dirname(__FILE__)}/testrepo/*"), repo, :preserve => true)
    
    hostname = `facter fqdn`.chomp
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
    
    puts "Created repository #{repo}"
    
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
  
  UNICORN = false
  def start_server(repo='no_repo_yet')
    # We want the running server's notion of the server base to be a symlink
    # that we can easily change later in swap_repository.
    serverbasefile = Tempfile.new('etchtest')
    serverbase = serverbasefile.path
    serverbasefile.close!
    File.symlink(repo, serverbase)
    ENV['etchserverbase'] = serverbase
    # Pick a random port in the 3001-6000 range (range somewhat randomly chosen)
    port = 3001 + rand(3000)
    if pid = fork
      # Give the server up to 30s to start, checking every second
      serverstarted = false
      catch :serverstarted do
        30.times do
          begin
            Net::HTTP.start('localhost', port) do |http|
              response = http.head("/")
              if response.kind_of?(Net::HTTPSuccess)
                serverstarted = true
                throw :serverstarted
              end
            end
          rescue => e
          end
          sleep(1)
        end
      end
      if !serverstarted
        raise "Etch server failed to start"
      end
    else
      if UNICORN
        exec("cd #{SERVERDIR} && #{RUBY} `which unicorn_rails` -p #{port}")
      else
        exec("cd #{SERVERDIR} && #{RUBY} ./script/server -p #{port}")
      end
    end
    {:port => port, :pid => pid, :repo => serverbase}
  end
  
  def stop_server(server)
    Process.kill('TERM', server[:pid])
    Process.waitpid(server[:pid])
  end
  
  def run_etch(server, testroot, options={})
    extra_args = ''
    if options[:extra_args]
      extra_args += options[:extra_args]
    end
    extra_args += " --debug"
    
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
    
    if options[:errors_expected]
      # Warn the user that errors are expected.  Otherwise it can be
      # disconcerting if you're watching the tests run and see errors.
      #sleep 3
      puts "#"
      puts "# Errors expected here"
      puts "#"
      #sleep 3
    end
    result = system("#{RUBY} -I #{CLIENTDIR}/lib #{CLIENTDIR}/bin/etch --generate-all --test-root=#{testroot} #{server} #{key} #{extra_args}")
    if options[:errors_expected]
      assert(!result, options[:testname])
    else
      assert(result, options[:testname])
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
      response = http.get("/results.xml?clients.name=#{hostname}&sort=created_at_reverse")
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
end

