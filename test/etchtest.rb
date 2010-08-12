#
# Module of code shared by all of the etch test cases
#

require 'test/unit'
require 'tempfile'
require 'fileutils'

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
    FileUtils.cp_r(Dir.glob("#{File.dirname(__FILE__)}/testrepo/*"), repo)
    
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
      # FIXME: replace this with a check that the server has started
      puts "Giving the server some time to start up"
      sleep(5)
    else
      if UNICORN
        exec("cd #{SERVERDIR} && unicorn_rails -p #{port}")
      else
        exec("cd #{SERVERDIR} && ./script/server -p #{port}")
      end
    end
    {:port => port, :pid => pid, :repo => serverbase}
  end
  
  def stop_server(server)
    Process.kill('TERM', server[:pid])
    Process.waitpid(server[:pid])
  end
  
  def run_etch(server, testbase, errors_expected=false, extra_args='')
    extra_args = extra_args + " --debug"
    if errors_expected
      # Warn the user that errors are expected.  Otherwise it can be
      # disconcerting if you're watching the tests run and see errors.
      #sleep 3
      puts "#"
      puts "# Errors expected here"
      puts "#"
      #sleep 3
    end
    result = system("ruby #{CLIENTDIR}/etch --generate-all --server=http://localhost:#{server[:port]} --test-base=#{testbase} --key=#{File.dirname(__FILE__)}/keys/testkey #{extra_args}")
    if errors_expected
      assert(!result)
    else
      assert(result)
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
end

