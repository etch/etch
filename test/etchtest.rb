#
# Module of code shared by all of the etch test cases
#

require 'tempfile'
require 'fileutils'

module EtchTests
  # Haven't found a Ruby method for creating temporary directories,
  # so create a temporary file and replace it with a directory.
  def tempdir
    tmpfile = Tempfile.new('etchtest')
    tmpdir = tmpfile.path
    tmpfile.close!
    Dir.mkdir(tmpdir)
    tmpdir
  end

  def initialize_repository(nodegroups = [])
    # Generate a temp directory to put our test repository into
    repodir = tempdir

    # Put the basic files into that directory needed for a basic etch tree
    FileUtils.cp_r(Dir.glob('testrepo/*'), repodir)

    hostname = `facter fqdn`.chomp
    nodegroups_string = ''
    nodegroups.each { |ng| nodegroups_string << "<group>#{ng}</group>\n" }
    File.open(File.join(repodir, 'nodes.xml'), 'w') do |file|
      file.puts <<-EOF
      <nodes>
        <node name="#{hostname}">
          #{nodegroups_string}
        </node>
      </nodes>
      EOF
    end
    
    puts "Created repository #{repodir}"
    
    repodir
  end

  def remove_repository(repodir)
    FileUtils.rm_rf(repodir)
  end

  def start_server(repodir)
    ENV['etchserverbase'] = repodir
    # Pick a random port in the 3001-6000 range (range somewhat randomly chosen)
    port = 3001 + rand(2999)
    if @serverpid = fork
      puts "Giving the server some time to start up"
      sleep(5)
    else
      Dir.chdir('../server/trunk')
      # Causes ruby to fork, so we're left with a useless pid
      #exec("./script/server -d -p #{port}")
      # Causes ruby to invoke a copy of sh to run the command (to handle
      # the redirect), which gets in the way of killing things
      #exec("./script/server -p #{port} > /dev/null")
      exec("./script/server -p #{port}")
    end
    port
  end

  def stop_server
    Process.kill('TERM', @serverpid)
    Process.waitpid(@serverpid)
  end

  def run_etch(port, testbase, errors_expected=false, extra_args='')
    #extra_args << " --debug"
    if errors_expected
      assert(!system("ruby ../client/trunk/etch --generate-all --server=http://localhost:#{port} --test-base=#{testbase} #{extra_args}"))
    else
      assert(system("ruby ../client/trunk/etch --generate-all --server=http://localhost:#{port} --test-base=#{testbase} #{extra_args}"))
    end
  end

  def get_file_contents(file)
    # Don't follow symlinks
    if File.file?(file) && !File.symlink?(file)
      # Trap exceptions (like non-existent file) so that tests can
      # properly report back whether the file contents match or not.
      begin
        IO.read(file)
      rescue
        nil
      end
    end
  end
end

