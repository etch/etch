##############################################################################
# Etch configuration file management tool library
##############################################################################

# Ensure we can find etch.rb if run within the development directory structure
#   This is roughly equivalent to "../server/lib"
serverlibdir = File.join(File.dirname(File.dirname(File.expand_path(__FILE__))), 'server', 'lib')
if File.exist?(serverlibdir)
  $:.unshift(serverlibdir)
end

begin
  # Try loading facter w/o gems first so that we don't introduce a
  # dependency on gems if it is not needed.
  require 'facter'    # Facter
rescue LoadError
  require 'rubygems'
  require 'facter'
end
require 'find'
require 'digest/sha1' # hexdigest
require 'openssl'     # OpenSSL
require 'base64'      # decode64, encode64
require 'uri'
require 'net/http'
require 'net/https'
require 'rexml/document'
require 'fileutils'   # copy, mkpath, rmtree
require 'fcntl'       # Fcntl::O_*
require 'etc'         # getpwnam, getgrnam
require 'tempfile'    # Tempfile
require 'cgi'
require 'timeout'
require 'logger'
require 'etch'

class Etch::Client
  VERSION = '1.18'
  
  CONFIRM_PROCEED = 1
  CONFIRM_SKIP = 2
  CONFIRM_QUIT = 3
  PRIVATE_KEY_PATHS = ["/etc/ssh/ssh_host_rsa_key", "/etc/ssh_host_rsa_key"]
  
  # We need these in relation to the output capturing
  ORIG_STDOUT = STDOUT.dup
  ORIG_STDERR = STDERR.dup
  
  attr_reader :exec_once_per_run
  
  def initialize(options)
    @server = options[:server] ? options[:server] : 'https://etch'
    @tag = options[:tag]
    @varbase = options[:varbase] ? options[:varbase] : '/var/etch'
    @local = options[:local]
    @debug = options[:debug]
    @dryrun = options[:dryrun]
    @interactive = options[:interactive]
    @filenameonly = options[:filenameonly]
    @fullfile = options[:fullfile]
    @key = options[:key] ? options[:key] : get_private_key_path
    @disableforce = options[:disableforce]
    @lockforce = options[:lockforce]
    
    # Ensure we have a sane path, particularly since we are often run from
    # cron.
    # FIXME: Read from config file
    ENV['PATH'] = '/bin:/usr/bin:/sbin:/usr/sbin:/opt/csw/bin:/opt/csw/sbin'
    
    @origbase    = File.join(@varbase, 'orig')
    @historybase = File.join(@varbase, 'history')
    @lockbase    = File.join(@varbase, 'locks')
    @requestbase = File.join(@varbase, 'requests')
    
    @facts = Facter.to_hash
    if @facts['operatingsystemrelease']
      # Some versions of Facter have a bug that leaves extraneous
      # whitespace on this fact.  Work around that with strip.  I.e. on
      # CentOS you'll get '5 ' or '5.2 '.
      @facts['operatingsystemrelease'].strip!
    end

    if @local
      logger = Logger.new(STDOUT)
      dlogger = Logger.new(STDOUT)
      if @debug
        dlogger.level = Logger::DEBUG
      else
        dlogger.level = Logger::INFO
      end
      @etch = Etch.new(logger, dlogger)
    else
      # Make sure the server URL ends in a / so that we can append paths
      # to it using URI.join
      if @server !~ %r{/$}
        @server << '/'
      end
      @filesuri   = URI.join(@server, 'files')
      @resultsuri = URI.join(@server, 'results')
    
      @blankrequest = {}
      # If the user specified a non-standard key then override the
      # sshrsakey fact so that authentication works
      if @key
        @facts['sshrsakey'] = IO.read(@key+'.pub').chomp.split[1]
      end
      @facts.each_pair { |key, value| @blankrequest["facts[#{key}]"] = value.to_s }
      @blankrequest['fqdn'] = @facts['fqdn']
      if @debug
        @blankrequest['debug'] = '1'
      end
      if @tag
        @blankrequest['tag'] = @tag
      end
    end
    
    @locked_files = {}
    @first_update = {}
    @already_processed = {}
    @exec_already_processed = {}
    @exec_once_per_run = {}
    @results = []
    # See start/stop_output_capture for these
    @output_pipes = []
    
    @lchown_supported = nil
    @lchmod_supported = nil
  end

  def process_until_done(files, commands)
    # Our overall status.  Will be reported to the server and used as the
    # return value for this method.  Command-line clients should use it as
    # their exit value.  Zero indicates no errors.
    status = 0
    message = ''
    
    # Prep http instance
    http = nil
    if !@local
      http = Net::HTTP.new(@filesuri.host, @filesuri.port)
      if @filesuri.scheme == "https"
        # Eliminate the OpenSSL "using default DH parameters" warning
        if File.exist?('/etc/etch/dhparams')
          dh = OpenSSL::PKey::DH.new(IO.read('/etc/etch/dhparams'))
          Net::HTTP.ssl_context_accessor(:tmp_dh_callback)
          http.tmp_dh_callback = proc { dh }
        end
        http.use_ssl = true
        if File.exist?('/etc/etch/ca.pem')
          http.ca_file = '/etc/etch/ca.pem'
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        elsif File.directory?('/etc/etch/ca')
          http.ca_path = '/etc/etch/ca'
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
      end
      http.start
    end
    
    # catch/throw for expected/non-error events that end processing
    # begin/raise for error events that end processing
    catch :stop_processing do
      begin
        enabled, message = check_for_disable_etch_file
        if !enabled
          # 200 is the arbitrarily picked exit value indicating
          # that etch is disabled
          status = 200
          throw :stop_processing
        end
        remove_stale_lock_files

        # Assemble the initial request
        request = nil
        if @local
          request = {}
          if files && !files.empty?
            request[:files] = {}
            files.each do |file|
              request[:files][file] = {:orig => save_orig(file)}
              local_requests = get_local_requests(file)
              if local_requests
                request[:files][file][:local_requests] = local_requests
              end
            end
          end
          if commands && !commands.empty?
            request[:commands] = {}
            commands.each do |command|
              request[:commands][command] = {}
            end
          end
        else
          request = get_blank_request
          if (files && !files.empty?) || (commands && !commands.empty?)
            if files
              files.each do |file|
                request["files[#{CGI.escape(file)}][sha1sum]"] =
                  get_orig_sum(file)
                local_requests = get_local_requests(file)
                if local_requests
                  request["files[#{CGI.escape(file)}][local_requests]"] =
                    local_requests
                end
              end
            end
            if commands
              commands.each do |command|
                request["commands[#{CGI.escape(command)}]"] = '1'
              end
            end
          else
            request['files[GENERATEALL]'] = '1'
          end
        end

        #
        # Loop back and forth with the server sending requests for files and
        # responding to the server's requests for original contents or sums
        # it needs
        #
        
        Signal.trap('EXIT') do
          STDOUT.reopen(ORIG_STDOUT)
          STDERR.reopen(ORIG_STDERR)
          unlock_all_files
        end
        
        10.times do
          #
          # Send request to server
          #
          
          responsedata = {}
          if @local
            results = @etch.generate(@local, @facts, request)
            # FIXME: Etch#generate returns parsed XML using whatever XML
            # library it happens to use.  In order to avoid re-parsing
            # the XML we'd have to use the XML abstraction code from Etch
            # everwhere here.
            # Until then re-parse the XML using REXML.
            #responsedata[:configs] = results[:configs]
            responsedata[:configs] = {}
            results[:configs].each {|f,c| responsedata[:configs][f] = REXML::Document.new(c.to_s) }
            responsedata[:need_sums] = {}
            responsedata[:need_origs] = results[:need_orig]
            #responsedata[:allcommands] = results[:allcommands]
            responsedata[:allcommands] = {}
            results[:allcommands].each {|cn,c| responsedata[:allcommands][cn] = REXML::Document.new(c.to_s) }
            responsedata[:retrycommands] = results[:retrycommands]
          else
            puts "Sending request to server #{@filesuri}: #{request.inspect}" if (@debug)
            post = Net::HTTP::Post.new(@filesuri.path)
            post.set_form_data(request)
            sign_post!(post, @key)
            response = http.request(post)
            if !response.kind_of?(Net::HTTPSuccess)
              $stderr.puts response.body
              # error! raises an exception
              response.error!
            end
            puts "Response from server:\n'#{response.body}'" if (@debug)
            if !response.body.nil? && !response.body.empty?
              response_xml = REXML::Document.new(response.body)
              responsedata[:configs] = {}
              response_xml.elements.each('/files/configs/config') do |config|
                file = config.attributes['filename']
                # We have to make a new document so that XPath paths are
                # referenced relative to the configuration for this
                # specific file.
                #responsedata[:configs][file] = REXML::Document.new(response_xml.elements["/files/configs/config[@filename='#{file}']"].to_s)
                responsedata[:configs][file] = REXML::Document.new(config.to_s)
              end
              responsedata[:need_sums] = {}
              response_xml.elements.each('/files/need_sums/need_sum') do |ns|
                responsedata[:need_sums][ns.text] = true
              end
              responsedata[:need_origs] = {}
              response_xml.elements.each('/files/need_origs/need_orig') do |no|
                responsedata[:need_origs][no.text] = true
              end
              responsedata[:allcommands] = {}
              response_xml.elements.each('/files/allcommands/commands') do |command|
                commandname = command.attributes['commandname']
                # We have to make a new document so that XPath paths are
                # referenced relative to the configuration for this
                # specific file.
                #responsedata[:allcommands][commandname] = REXML::Document.new(response_xml.root.elements["/files/allcommands/commands[@commandname='#{commandname}']"].to_s)
                responsedata[:allcommands][commandname] = REXML::Document.new(command.to_s)
              end
              responsedata[:retrycommands] = {}
              response_xml.elements.each('/files/retrycommands/retrycommand') do |rc|
                responsedata[:retrycommands][rc.text] = true
              end
            else
              puts "  Response is empty" if (@debug)
              break
            end
          end

          #
          # Process the response from the server
          #

          # Prep a clean request hash
          if @local
            request = {}
            if !responsedata[:need_origs].empty?
              request[:files] = {}
            end
          else
            request = get_blank_request
          end

          # With generateall we expect to make at least two round trips
          # to the server.
          # 1) Send GENERATEALL request, get back a list of need_sums
          # 2) Send sums, possibly get back some need_origs
          # 3) Send origs, get back generated files
          need_to_loop = false
          reset_already_processed
          # Process configs first, as they may contain setup entries that are
          # needed to create the original files.
          responsedata[:configs].each_key do |file|
            puts "Processing config for #{file}" if (@debug)
            continue_processing = process_file(file, responsedata)
            if !continue_processing
              throw :stop_processing
            end
          end
          responsedata[:need_sums].each_key do |need_sum|
            puts "Processing request for sum of #{need_sum}" if (@debug)
            if @local
              # If this happens we screwed something up, the local mode
              # code never requests sums.
              raise "No support for sums in local mode"
            else
              request["files[#{CGI.escape(need_sum)}][sha1sum]"] =
                get_orig_sum(need_sum)
            end
            local_requests = get_local_requests(need_sum)
            if local_requests
              if @local
                request[:files][need_sum][:local_requests] = local_requests
              else
                request["files[#{CGI.escape(need_sum)}][local_requests]"] =
                  local_requests
              end
            end
            need_to_loop = true
          end
          responsedata[:need_origs].each_key do |need_orig|
            puts "Processing request for contents of #{need_orig}" if (@debug)
            if @local
              request[:files][need_orig] = {:orig => save_orig(need_orig)}
            else
              request["files[#{CGI.escape(need_orig)}][contents]"] =
                Base64.encode64(get_orig_contents(need_orig))
              request["files[#{CGI.escape(need_orig)}][sha1sum]"] =
                get_orig_sum(need_orig)
            end
            local_requests = get_local_requests(need_orig)
            if local_requests
              if @local
                request[:files][need_orig][:local_requests] = local_requests
              else
                request["files[#{CGI.escape(need_orig)}][local_requests]"] =
                  local_requests
              end
            end
            need_to_loop = true
          end
         responsedata[:allcommands].each_key do |commandname|
            puts "Processing commands #{commandname}" if (@debug)
            continue_processing = process_commands(commandname, responsedata)
            if !continue_processing
              throw :stop_processing
            end
          end
          responsedata[:retrycommands].each_key do |commandname|
            puts "Processing request to retry command #{commandname}" if (@debug)
            if @local
              request[:commands][commandname] = true
            else
              request["commands[#{CGI.escape(commandname)}]"] = '1'
            end
            need_to_loop = true
          end
          
          if !need_to_loop
            break
          end
        end

        puts "Processing 'exec once per run' commands" if (!exec_once_per_run.empty?)
        exec_once_per_run.keys.each do |exec|
          process_exec('post', exec)
        end
      rescue Exception => e
        status = 1
        $stderr.puts e.message
        $stderr.puts e.backtrace.join("\n") if @debug
      end  # begin/rescue
    end  # catch
    
    # Send results to server
    if !@dryrun && !@local
      rails_results = []
      # A few of the fields here are numbers or booleans and need a
      # to_s to make them compatible with CGI.escape, which expects a
      # string.
      rails_results << "fqdn=#{CGI.escape(@facts['fqdn'])}"
      rails_results << "status=#{CGI.escape(status.to_s)}"
      rails_results << "message=#{CGI.escape(message)}"
      @results.each do |result|
        # Strangely enough this works.  Even though the key is not unique to
        # each result the Rails parameter parsing code keeps track of keys it
        # has seen, and if it sees a duplicate it starts a new hash.
        rails_results << "results[][file]=#{CGI.escape(result['file'])}"
        rails_results << "results[][success]=#{CGI.escape(result['success'].to_s)}"
        rails_results << "results[][message]=#{CGI.escape(result['message'])}"
      end
      puts "Sending results to server #{@resultsuri}" if (@debug)
      resultspost = Net::HTTP::Post.new(@resultsuri.path)
      # We have to bypass Net::HTTP's set_form_data method in this case
      # because it expects a hash and we can't provide the results in the
      # format we want in a hash because we'd have duplicate keys (see above).
      results_as_string = rails_results.join('&')
      resultspost.body = results_as_string
      resultspost.content_type = 'application/x-www-form-urlencoded'
      sign_post!(resultspost, @key)
      response = http.request(resultspost)
      case response
      when Net::HTTPSuccess
        puts "Response from server:\n'#{response.body}'" if (@debug)
      else
        $stderr.puts "Error submitting results:"
        $stderr.puts response.body
      end
    end
    
    status
  end

  def check_for_disable_etch_file
    disable_etch = File.join(@varbase, 'disable_etch')
    message = ''
    if File.exist?(disable_etch)
      if !@disableforce
        message = "Etch disabled:\n"
        message << IO.read(disable_etch)
        puts message
        return false, message
      else
        puts "Ignoring disable_etch file"
      end
    end
    return true, message
  end
  
  def get_blank_request
    @blankrequest.dup
  end
  
  # Raises an exception if any fatal error is encountered
  # Returns a boolean, true unless the user indicated in interactive mode
  # that further processing should be halted
  def process_file(file, responsedata)
    continue_processing = true
    save_results = true
    exception = nil
    
    # We may not have configuration for this file, if it does not apply
    # to this host.  The server takes care of detecting any errors that
    # might involve, so here we can just silently return.
    config = responsedata[:configs][file]
    if !config
      puts "No configuration for #{file}, skipping" if (@debug)
      return continue_processing
    end
        
    # Skip files we've already processed in response to <depend>
    # statements.
    if @already_processed.has_key?(file)
      puts "Skipping already processed #{file}" if (@debug)
      return continue_processing
    end
    
    # Prep the results capturing for this file
    result = {}
    result['file'] = file
    result['success'] = true
    result['message'] = ''
    
    # catch/throw for expected/non-error events that end processing
    # begin/raise for error events that end processing
    # Within this block you should throw :process_done if you've reached
    # a natural stopping point and nothing further needs to be done.  You
    # should raise an exception if you encounter an error condition.
    # Do not 'return' or 'abort'.
    catch :process_done do
      begin
        start_output_capture
    
        puts "Processing #{file}" if (@debug)
    
        # The %locked_files hash provides a convenient way to
        # detect circular dependancies.  It doesn't give us an ordered
        # list of dependencies, which might be handy to help the user
        # debug the problem, but I don't think it's worth maintaining a
        # seperate array just for that purpose.
        if @locked_files.has_key?(file)
          raise "Circular dependancy detected.  " +
            "Dependancy list (unsorted) contains:\n  " +
            @locked_files.keys.join(', ')
        end

        # This needs to be after the circular dependency check
        lock_file(file)
        
        # Process any other files that this file depends on
        config.elements.each('/config/depend') do |depend|
          puts "Processing dependency #{depend.text}" if (@debug)
          process_file(depend.text, responsedata)
        end
        
        # Process any commands that this file depends on
        config.elements.each('/config/dependcommand') do |dependcommand|
          puts "Processing command dependency #{dependcommand.text}" if (@debug)
          process_commands(dependcommand.text, responsedata)
        end
        
        # See what type of action the user has requested

        # Check to see if the user has requested that we revert back to the
        # original file.
        if config.elements['/config/revert']
          origpathbase = File.join(@origbase, file)

          # Restore the original file if it is around
          if File.exist?("#{origpathbase}.ORIG")
            origpath = "#{origpathbase}.ORIG"
            origdir = File.dirname(origpath)
            origbase = File.basename(origpath)
            filedir = File.dirname(file)

            # Remove anything we might have written out for this file
            remove_file(file) if (!@dryrun)

            puts "Restoring #{origpath} to #{file}"
            recursive_copy_and_rename(origdir, origbase, file) if (!@dryrun)

            # Now remove the backed-up original so that future runs
            # don't do anything
            remove_file(origpath) if (!@dryrun)
          elsif File.exist?("#{origpathbase}.TAR")
            origpath = "#{origpathbase}.TAR"
            filedir = File.dirname(file)

            # Remove anything we might have written out for this file
            remove_file(file) if (!@dryrun)

            puts "Restoring #{file} from #{origpath}"
            system("cd #{filedir} && tar xf #{origpath}") if (!@dryrun)

            # Now remove the backed-up original so that future runs
            # don't do anything
            remove_file(origpath) if (!@dryrun)
          elsif File.exist?("#{origpathbase}.NOORIG")
            origpath = "#{origpathbase}.NOORIG"
            puts "Original #{file} didn't exist, restoring that state"

            # Remove anything we might have written out for this file
            remove_file(file) if (!@dryrun)

            # Now remove the backed-up original so that future runs
            # don't do anything
            remove_file(origpath) if (!@dryrun)
          end

          throw :process_done
        end

        # Perform any setup commands that the user has requested.
        # These are occasionally needed to install software that is
        # required to generate the file (think m4 for sendmail.cf) or to
        # install a package containing a sample config file which we
        # then edit with a script, and thus doing the install in <pre>
        # is too late.
        if config.elements['/config/setup']
          process_setup(file, config)
        end

        if config.elements['/config/file']  # Regular file
          newcontents = nil
          if config.elements['/config/file/contents']
            newcontents = Base64.decode64(config.elements['/config/file/contents'].text)
          end

          permstring = config.elements['/config/file/perms'].text
          perms = permstring.oct
          owner = config.elements['/config/file/owner'].text
          group = config.elements['/config/file/group'].text
          uid = lookup_uid(owner)
          gid = lookup_gid(group)

          set_file_contents = false
          if newcontents
            set_file_contents = compare_file_contents(file, newcontents)
          end
          set_permissions = nil
          set_ownership = nil
          # If the file is currently something other than a plain file then
          # always set the flags to set the permissions and ownership.
          # Checking the permissions/ownership of whatever is there currently
          # is useless.
          if set_file_contents && (!File.file?(file) || File.symlink?(file))
            set_permissions = true
            set_ownership = true
          else
            set_permissions = compare_permissions(file, perms)
            set_ownership = compare_ownership(file, uid, gid)
          end

          # Proceed if:
          # - The new contents are different from the current file
          # - The permissions or ownership requested don't match the
          #   current permissions or ownership
          if !set_file_contents &&
             !set_permissions &&
             !set_ownership
            puts "No change to #{file} necessary" if (@debug)
            throw :process_done
          else
            # Tell the user what we're going to do
            if set_file_contents
              # If the new contents are different from the current file
              # show that to the user in the format they've requested.
              # If the requested permissions are not world-readable then
              # use the filenameonly format so that we don't disclose
              # non-public data, unless we're in interactive mode
              if @filenameonly || (permstring.to_i(8) & 0004 == 0 && !@interactive)
                puts "Will write out new #{file}"
              elsif @fullfile
                # Grab the first 8k of the contents
                first8k = newcontents.slice(0, 8192)
                # Then check it for null characters.  If it has any it's
                # likely a binary file.
                hasnulls = true if (first8k =~ /\0/)

                if !hasnulls
                  puts "Generated contents for #{file}:"
                  puts "============================================="
                  puts newcontents
                  puts "============================================="
                else
                  puts "Will write out new #{file}, but " +
                       "generated contents are not plain text so " +
                       "they will not be displayed"
                end
              else
                # Default is to show a diff of the current file and the
                # newly generated file.
                puts "Will make the following changes to #{file}, diff -c:"
                tempfile = Tempfile.new(File.basename(file))
                tempfile.write(newcontents)
                tempfile.close
                puts "============================================="
                if File.file?(file) && !File.symlink?(file)
                  system("diff -c #{file} #{tempfile.path}")
                else
                  # Either the file doesn't currently exist,
                  # or is something other than a normal file
                  # that we'll be replacing with a file.  In
                  # either case diffing against /dev/null will
                  # produce the most logical output.
                  system("diff -c /dev/null #{tempfile.path}")
                end
                puts "============================================="
                tempfile.delete
              end
            end
            if set_permissions
              puts "Will set permissions on #{file} to #{permstring}"
            end
            if set_ownership
              puts "Will set ownership of #{file} to #{uid}:#{gid}"
            end

            # If the user requested interactive mode ask them for
            # confirmation to proceed.
            if @interactive
              case get_user_confirmation()
              when CONFIRM_PROCEED
                # No need to do anything
              when CONFIRM_SKIP
                save_results = false
                throw :process_done
              when CONFIRM_QUIT
                unlock_all_files
                continue_processing = false
                save_results = false
                throw :process_done
              else
                raise "Unexpected result from get_user_confirmation()"
              end
            end

            # Perform any pre-action commands that the user has requested
            if config.elements['/config/pre']
              process_pre(file, config)
            end

            # If the original "file" is a directory and the user hasn't
            # specifically told us we can overwrite it then raise an exception.
            # 
            # The test is here, rather than a bit earlier where you might
            # expect it, because the pre section may be used to address
            # originals which are directories.  So we don't check until
            # after any pre commands are run.
            if File.directory?(file) && !File.symlink?(file) &&
               !config.elements['/config/file/overwrite_directory']
              raise "Can't proceed, original of #{file} is a directory,\n" +
                    "  consider the overwrite_directory flag if appropriate."
            end

            # Give save_orig a definitive answer on whether or not to save the
            # contents of an original directory.
            origpath = save_orig(file, true)
            # Update the history log
            save_history(file)

            # Make sure the directory tree for this file exists
            filedir = File.dirname(file)
            if !File.directory?(filedir)
              puts "Making directory tree #{filedir}"
              FileUtils.mkpath(filedir) if (!@dryrun)
            end

            # Make a backup in case we need to roll back.  We have no use
            # for a backup if there are no test commands defined (since we
            # only use the backup to roll back if the test fails), so don't
            # bother to create a backup unless there is a test command defined.
            backup = nil
            if config.elements['/config/test_before_post'] ||
               config.elements['/config/test']
              backup = make_backup(file)
              puts "Created backup #{backup}"
            end

            # If the new contents are different from the current file,
            # replace the file.
            if set_file_contents
              if !@dryrun
                # Write out the new contents into a temporary file
                filebase = File.basename(file)
                filedir = File.dirname(file)
                newfile = Tempfile.new(filebase, filedir)

                # Set the proper permissions on the file before putting
                # data into it.
                newfile.chmod(perms)
                begin
                  newfile.chown(uid, gid)
                rescue Errno::EPERM
                  raise if Process.euid == 0
                end

                puts "Writing new contents of #{file} to #{newfile.path}" if (@debug)
                newfile.write(newcontents)
                newfile.close

                # If the current file is not a plain file, remove it.
                # Plain files are left alone so that the replacement is
                # atomic.
                if File.symlink?(file) || (File.exist?(file) && ! File.file?(file))
                  puts "Current #{file} is not a plain file, removing it" if (@debug)
                  remove_file(file)
                end

                # Move the new file into place
                File.rename(newfile.path, file)
          
                # Check the permissions and ownership now to ensure they
                # end up set properly
                set_permissions = compare_permissions(file, perms)
                set_ownership = compare_ownership(file, uid, gid)
              end
            end

            # Ensure the permissions are set properly
            if set_permissions
              File.chmod(perms, file) if (!@dryrun)
            end

            # Ensure the ownership is set properly
            if set_ownership
              begin
                File.chown(uid, gid, file) if (!@dryrun)
              rescue Errno::EPERM
                raise if Process.euid == 0
              end
            end

            # Perform any test_before_post commands that the user has requested
            if config.elements['/config/test_before_post']
              if !process_test_before_post(file, config)
                restore_backup(file, backup)
                raise "test_before_post failed"
              end
            end

            # Perform any post-action commands that the user has requested
            if config.elements['/config/post']
              process_post(file, config)
            end

            # Perform any test commands that the user has requested
            if config.elements['/config/test']
              if !process_test(file, config)
                restore_backup(file, backup)

                # Re-run any post commands
                if config.elements['/config/post']
                  process_post(file, config)
                end
              end
            end

            # Clean up the backup, we don't need it anymore
            if config.elements['/config/test_before_post'] ||
               config.elements['/config/test']
              puts "Removing backup #{backup}"
              remove_file(backup) if (!@dryrun)
            end

            # Update the history log again
            save_history(file)

            throw :process_done
          end
        end

        if config.elements['/config/link']  # Symbolic link

          dest = config.elements['/config/link/dest'].text

          set_link_destination = !compare_link_destination(file, dest)
          absdest = File.expand_path(dest, File.dirname(file))

          permstring = config.elements['/config/link/perms'].text
          perms = permstring.oct
          owner = config.elements['/config/link/owner'].text
          group = config.elements['/config/link/group'].text
          uid = lookup_uid(owner)
          gid = lookup_gid(group)
    
          # lchown and lchmod are not supported on many platforms.  The server
          # always includes ownership and permissions settings with any link
          # (pulling them from defaults.xml if the user didn't specify them in
          # the config.xml file.)  As such link management would always fail
          # on systems which don't support lchown/lchmod, which seems like bad
          # behavior.  So instead we check to see if they are implemented, and
          # if not just ignore ownership/permissions settings.  I suppose the
          # ideal would be for the server to tell the client whether the
          # ownership/permissions were specifically requested (in config.xml)
          # rather than just defaults, and then for the client to always try to
          # manage ownership/permissions if the settings are not defaults (and
          # fail in the event that they aren't implemented.)
          if @lchown_supported.nil?
            lchowntestlink = Tempfile.new('etchlchowntest').path
            lchowntestfile = Tempfile.new('etchlchowntest').path
            File.delete(lchowntestlink)
            File.symlink(lchowntestfile, lchowntestlink)
            begin
              File.lchown(0, 0, lchowntestfile)
              @lchown_supported = true
            rescue NotImplementedError
              @lchown_supported = false
            rescue Errno::EPERM
              raise if Process.euid == 0
            end
            File.delete(lchowntestlink)
          end
          if @lchmod_supported.nil?
            lchmodtestlink = Tempfile.new('etchlchmodtest').path
            lchmodtestfile = Tempfile.new('etchlchmodtest').path
            File.delete(lchmodtestlink)
            File.symlink(lchmodtestfile, lchmodtestlink)
            begin
              File.lchmod(0644, lchmodtestfile)
              @lchmod_supported = true        
            rescue NotImplementedError
              @lchmod_supported = false
            end
            File.delete(lchmodtestlink)
          end
    
          set_permissions = false
          if @lchmod_supported
            # If the file is currently something other than a link then
            # always set the flags to set the permissions and ownership.
            # Checking the permissions/ownership of whatever is there currently
            # is useless.
            if set_link_destination && !File.symlink?(file)
              set_permissions = true
            else
              set_permissions = compare_permissions(file, perms)
            end
          end
          set_ownership = false
          if @lchown_supported
            if set_link_destination && !File.symlink?(file)
              set_ownership = true
            else
              set_ownership = compare_ownership(file, uid, gid)
            end
          end

          # Proceed if:
          # - The new link destination differs from the current one
          # - The permissions or ownership requested don't match the
          #   current permissions or ownership
          if !set_link_destination &&
             !set_permissions &&
             !set_ownership
            puts "No change to #{file} necessary" if (@debug)
            throw :process_done
          # Check that the link destination exists, and refuse to create
          # the link unless it does exist or the user told us to go ahead
          # anyway.
          # 
          # Note that the destination may be a relative path, and the
          # target directory may not exist yet, so we have to convert the
          # destination to an absolute path and test that for existence.
          # expand_path should handle paths that are already absolute
          # properly.
          elsif ! File.exist?(absdest) && ! File.symlink?(absdest) &&
                ! config.elements['/config/link/allow_nonexistent_dest']
            puts "Destination #{dest} for link #{file} does not exist," +
                 "  consider the allow_nonexistent_dest flag if appropriate."
            throw :process_done
          else
            # Tell the user what we're going to do
            if set_link_destination
              puts "Linking #{file} -> #{dest}"
            end
            if set_permissions
              puts "Will set permissions on #{file} to #{permstring}"
            end
            if set_ownership
              puts "Will set ownership of #{file} to #{uid}:#{gid}"
            end

            # If the user requested interactive mode ask them for
            # confirmation to proceed.
            if @interactive
              case get_user_confirmation()
              when CONFIRM_PROCEED
                # No need to do anything
              when CONFIRM_SKIP
                save_results = false
                throw :process_done
              when CONFIRM_QUIT
                unlock_all_files
                continue_processing = false
                save_results = false
                throw :process_done
              else
                raise "Unexpected result from get_user_confirmation()"
              end
            end

            # Perform any pre-action commands that the user has requested
            if config.elements['/config/pre']
              process_pre(file, config)
            end

            # If the original "file" is a directory and the user hasn't
            # specifically told us we can overwrite it then raise an exception.
            # 
            # The test is here, rather than a bit earlier where you might
            # expect it, because the pre section may be used to address
            # originals which are directories.  So we don't check until
            # after any pre commands are run.
            if File.directory?(file) && !File.symlink?(file) &&
               !config.elements['/config/link/overwrite_directory']
              raise "Can't proceed, original of #{file} is a directory,\n" +
                    "  consider the overwrite_directory flag if appropriate."
            end

            # Give save_orig a definitive answer on whether or not to save the
            # contents of an original directory.
            origpath = save_orig(file, true)
            # Update the history log
            save_history(file)

            # Make sure the directory tree for this link exists
            filedir = File.dirname(file)
            if !File.directory?(filedir)
              puts "Making directory tree #{filedir}"
              FileUtils.mkpath(filedir) if (!@dryrun)
            end

            # Make a backup in case we need to roll back.  We have no use
            # for a backup if there are no test commands defined (since we
            # only use the backup to roll back if the test fails), so don't
            # bother to create a backup unless there is a test command defined.
            backup = nil
            if config.elements['/config/test_before_post'] ||
               config.elements['/config/test']
              backup = make_backup(file)
              puts "Created backup #{backup}"
            end

            # Create the link
            if set_link_destination
              remove_file(file) if (!@dryrun)
              File.symlink(dest, file) if (!@dryrun)

              # Check the permissions and ownership now to ensure they
              # end up set properly
              if @lchmod_supported
                set_permissions = compare_permissions(file, perms)
              end
              if @lchown_supported
                set_ownership = compare_ownership(file, uid, gid)
              end
            end

            # Ensure the permissions are set properly
            if set_permissions
              # Note: lchmod
              File.lchmod(perms, file) if (!@dryrun)
            end

            # Ensure the ownership is set properly
            if set_ownership
              begin
                # Note: lchown
                File.lchown(uid, gid, file) if (!@dryrun)
              rescue Errno::EPERM
                raise if Process.euid == 0
              end
            end

            # Perform any test_before_post commands that the user has requested
            if config.elements['/config/test_before_post']
              if !process_test_before_post(file, config)
                restore_backup(file, backup)
                raise "test_before_post failed"
              end
            end

            # Perform any post-action commands that the user has requested
            if config.elements['/config/post']
              process_post(file, config)
            end

            # Perform any test commands that the user has requested
            if config.elements['/config/test']
              if !process_test(file, config)
                restore_backup(file, backup)

                # Re-run any post commands
                if config.elements['/config/post']
                  process_post(file, config)
                end
              end
            end

            # Clean up the backup, we don't need it anymore
            if config.elements['/config/test_before_post'] ||
               config.elements['/config/test']
              puts "Removing backup #{backup}"
              remove_file(backup) if (!@dryrun)
            end

            # Update the history log again
            save_history(file)

            throw :process_done
          end
        end

        if config.elements['/config/directory']  # Directory
  
          # A little safety check
          create = config.elements['/config/directory/create']
          raise "No create element found in directory section" if !create
  
          permstring = config.elements['/config/directory/perms'].text
          perms = permstring.oct
          owner = config.elements['/config/directory/owner'].text
          group = config.elements['/config/directory/group'].text
          uid = lookup_uid(owner)
          gid = lookup_gid(group)

          set_directory = !File.directory?(file) || File.symlink?(file)
          set_permissions = nil
          set_ownership = nil
          # If the file is currently something other than a directory then
          # always set the flags to set the permissions and ownership.
          # Checking the permissions/ownership of whatever is there currently
          # is useless.
          if set_directory
            set_permissions = true
            set_ownership = true
          else
            set_permissions = compare_permissions(file, perms)
            set_ownership = compare_ownership(file, uid, gid)
          end

          # Proceed if:
          # - The current file is not a directory
          # - The permissions or ownership requested don't match the
          #   current permissions or ownership
          if !set_directory &&
             !set_permissions &&
             !set_ownership
            puts "No change to #{file} necessary" if (@debug)
            throw :process_done
          else
            # Tell the user what we're going to do
            if set_directory
              puts "Making directory #{file}"
            end
            if set_permissions
              puts "Will set permissions on #{file} to #{permstring}"
            end
            if set_ownership
              puts "Will set ownership of #{file} to #{uid}:#{gid}"
            end

            # If the user requested interactive mode ask them for
            # confirmation to proceed.
            if @interactive
              case get_user_confirmation()
              when CONFIRM_PROCEED
                # No need to do anything
              when CONFIRM_SKIP
                save_results = false
                throw :process_done
              when CONFIRM_QUIT
                unlock_all_files
                continue_processing = false
                save_results = false
                throw :process_done
              else
                raise "Unexpected result from get_user_confirmation()"
              end
            end

            # Perform any pre-action commands that the user has requested
            if config.elements['/config/pre']
              process_pre(file, config)
            end

            # Give save_orig a definitive answer on whether or not to save the
            # contents of an original directory.
            origpath = save_orig(file, false)
            # Update the history log
            save_history(file)

            # Make sure the directory tree for this directory exists
            filedir = File.dirname(file)
            if !File.directory?(filedir)
              puts "Making directory tree #{filedir}"
              FileUtils.mkpath(filedir) if (!@dryrun)
            end

            # Make a backup in case we need to roll back.  We have no use
            # for a backup if there are no test commands defined (since we
            # only use the backup to roll back if the test fails), so don't
            # bother to create a backup unless there is a test command defined.
            backup = nil
            if config.elements['/config/test_before_post'] ||
               config.elements['/config/test']
              backup = make_backup(file)
              puts "Created backup #{backup}"
            end

            # Create the directory
            if set_directory
              remove_file(file) if (!@dryrun)
              Dir.mkdir(file) if (!@dryrun)

              # Check the permissions and ownership now to ensure they
              # end up set properly
              set_permissions = compare_permissions(file, perms)
              set_ownership = compare_ownership(file, uid, gid)
            end

            # Ensure the permissions are set properly
            if set_permissions
              File.chmod(perms, file) if (!@dryrun)
            end

            # Ensure the ownership is set properly
            if set_ownership
              begin
                File.chown(uid, gid, file) if (!@dryrun)
              rescue Errno::EPERM
                raise if Process.euid == 0
              end
            end

            # Perform any test_before_post commands that the user has requested
            if config.elements['/config/test_before_post']
              if !process_test_before_post(file, config)
                restore_backup(file, backup)
                raise "test_before_post failed"
              end
            end

            # Perform any post-action commands that the user has requested
            if config.elements['/config/post']
              process_post(file, config)
            end

            # Perform any test commands that the user has requested
            if config.elements['/config/test']
              if !process_test(file, config)
                restore_backup(file, backup)

                # Re-run any post commands
                if config.elements['/config/post']
                  process_post(file, config)
                end
              end
            end

            # Clean up the backup, we don't need it anymore
            if config.elements['/config/test_before_post'] ||
               config.elements['/config/test']
              puts "Removing backup #{backup}"
              remove_file(backup) if (!@dryrun)
            end

            # Update the history log again
            save_history(file)

            throw :process_done
          end
        end

        if config.elements['/config/delete']  # Delete whatever is there

          # A little safety check
          proceed = config.elements['/config/delete/proceed']
          raise "No proceed element found in delete section" if !proceed

          # Proceed only if the file currently exists
          if !File.exist?(file) && !File.symlink?(file)
            throw :process_done
          else
            # Tell the user what we're going to do
            puts "Removing #{file}"

            # If the user requested interactive mode ask them for
            # confirmation to proceed.
            if @interactive
              case get_user_confirmation()
              when CONFIRM_PROCEED
                # No need to do anything
              when CONFIRM_SKIP
                save_results = false
                throw :process_done
              when CONFIRM_QUIT
                unlock_all_files
                continue_processing = false
                save_results = false
                throw :process_done
              else
                raise "Unexpected result from get_user_confirmation()"
              end
            end

            # Perform any pre-action commands that the user has requested
            if config.elements['/config/pre']
              process_pre(file, config)
            end

            # If the original "file" is a directory and the user hasn't
            # specifically told us we can overwrite it then raise an exception.
            # 
            # The test is here, rather than a bit earlier where you might
            # expect it, because the pre section may be used to address
            # originals which are directories.  So we don't check until
            # after any pre commands are run.
            if File.directory?(file) && !File.symlink?(file) &&
               !config.elements['/config/delete/overwrite_directory']
              raise "Can't proceed, original of #{file} is a directory,\n" +
                    "  consider the overwrite_directory flag if appropriate."
            end

            # Give save_orig a definitive answer on whether or not to save the
            # contents of an original directory.
            origpath = save_orig(file, true)
            # Update the history log
            save_history(file)

            # Make a backup in case we need to roll back.  We have no use
            # for a backup if there are no test commands defined (since we
            # only use the backup to roll back if the test fails), so don't
            # bother to create a backup unless there is a test command defined.
            backup = nil
            if config.elements['/config/test_before_post'] ||
               config.elements['/config/test']
              backup = make_backup(file)
              puts "Created backup #{backup}"
            end

            # Remove the file
            remove_file(file) if (!@dryrun)

            # Perform any test_before_post commands that the user has requested
            if config.elements['/config/test_before_post']
              if !process_test_before_post(file, config)
                restore_backup(file, backup)
                raise "test_before_post failed"
              end
            end

            # Perform any post-action commands that the user has requested
            if config.elements['/config/post']
              process_post(file, config)
            end

            # Perform any test commands that the user has requested
            if config.elements['/config/test']
              if !process_test(file, config)
                restore_backup(file, backup)

                # Re-run any post commands
                if config.elements['/config/post']
                  process_post(file, config)
                end
              end
            end

            # Clean up the backup, we don't need it anymore
            if config.elements['/config/test_before_post'] ||
               config.elements['/config/test']
              puts "Removing backup #{backup}"
              remove_file(backup) if (!@dryrun)
            end

            # Update the history log again
            save_history(file)

            throw :process_done
          end
        end
      rescue Exception
        result['success'] = false
        exception = $!
      end # End begin block
    end  # End :process_done catch block
    
    unlock_file(file)
    
    output = stop_output_capture
    if exception
      output << exception.message
      output << exception.backtrace.join("\n") if @debug
    end
    result['message'] << output
    if save_results
      @results << result
    end
    
    if exception
      raise exception
    end
    
    @already_processed[file] = true

    continue_processing
  end

  # Raises an exception if any fatal error is encountered
  # Returns a boolean, true unless the user indicated in interactive mode
  # that further processing should be halted
  def process_commands(commandname, responsedata)
    continue_processing = true
    save_results = true
    exception = nil
    
    # We may not have configuration for this file, if it does not apply
    # to this host.  The server takes care of detecting any errors that
    # might involve, so here we can just silently return.
    command = responsedata[:allcommands][commandname]
    if !command
      puts "No configuration for command #{commandname}, skipping" if (@debug)
      return continue_processing
    end
        
    # Skip commands we've already processed in response to <depend>
    # statements.
    if @already_processed.has_key?(commandname)
      puts "Skipping already processed command #{commandname}" if (@debug)
      return continue_processing
    end
    
    # Prep the results capturing for this command
    result = {}
    result['file'] = commandname
    result['success'] = true
    result['message'] = ''
    
    # catch/throw for expected/non-error events that end processing
    # begin/raise for error events that end processing
    # Within this block you should throw :process_done if you've reached
    # a natural stopping point and nothing further needs to be done.  You
    # should raise an exception if you encounter an error condition.
    # Do not 'return' or 'abort'.
    catch :process_done do
      begin
        start_output_capture
        
        puts "Processing command #{commandname}" if (@debug)
        
        # The %locked_files hash provides a convenient way to
        # detect circular dependancies.  It doesn't give us an ordered
        # list of dependencies, which might be handy to help the user
        # debug the problem, but I don't think it's worth maintaining a
        # seperate array just for that purpose.
        if @locked_files.has_key?(commandname)
          raise "Circular command dependancy detected.  " +
            "Dependancy list (unsorted) contains:\n  " +
            @locked_files.keys.join(', ')
        end
        
        # This needs to be after the circular dependency check
        lock_file(commandname)
        
        # Process any other commands that this command depends on
        command.elements.each('/commands/depend') do |depend|
          puts "Processing command dependency #{depend.text}" if (@debug)
          process_commands(depend.text, responsedata)
        end
        
        # Process any files that this command depends on
        command.elements.each('/commands/dependfile') do |dependfile|
          puts "Processing file dependency #{dependfile.text}" if (@debug)
          process_file(dependfile.text, responsedata)
        end
        
        # Perform each step
        command.elements.each('/commands/step') do |step|
          guard = step.elements['guard/exec'].text
          command = step.elements['command/exec'].text
          
          # Run guard, display only in debug (a la setup)
          guard_result = process_guard(guard, commandname)
          
          if !guard_result
            # If the user requested interactive mode ask them for
            # confirmation to proceed.
            if @interactive
              case get_user_confirmation()
              when CONFIRM_PROCEED
                # No need to do anything
              when CONFIRM_SKIP
                save_results = false
                throw :process_done
              when CONFIRM_QUIT
                unlock_all_files
                continue_processing = false
                save_results = false
                throw :process_done
              else
                raise "Unexpected result from get_user_confirmation()"
              end
            end
            
            # Run command, always display (a la pre/post)
            process_command(command, commandname)
            
            # Re-run guard, always display, abort if fails
            guard_recheck_result = process_guard(guard, commandname)
            if !guard_recheck_result
              raise "Guard #{guard} still fails for #{commandname} after running command #{command}"
            end
          end
        end
      rescue Exception
        result['success'] = false
        exception = $!
      end # End begin block
    end  # End :process_done catch block
    
    unlock_file(commandname)
    
    output = stop_output_capture
    if exception
      output << exception.message
      output << exception.backtrace.join("\n") if @debug
    end
    result['message'] << output
    if save_results
      @results << result
    end
    
    if exception
      raise exception
    end
    
    @already_processed[commandname] = true
    
    continue_processing
  end
  
  # Returns true if the new contents are different from the current file,
  # or if the file does not currently exist.
  def compare_file_contents(file, newcontents)
    r = false

    # If the file currently exists and is a regular file, check to see
    # if the new contents are different.
    if File.file?(file) && !File.symlink?(file)
      contents = IO.read(file)
      if newcontents != contents
        r = true
      end
    else
      # The file doesn't currently exist or isn't a regular file
      r = true
    end

    r
  end

  # Returns true if the given file is a symlink which points to the given
  # destination, false if the link destination is different or if the file is
  # not a link or does not currently exist.
  def compare_link_destination(file, newdest)
    # If the file currently exists and is a link, check to see if the
    # new destination is different.
    if File.symlink?(file)
      currentdest = File.readlink(file)
      if currentdest == newdest
        return true
      end
    end
    false
  end

  def get_orig_sum(file)
    Digest::SHA1.hexdigest(get_orig_contents(file))
  end
  def get_orig_contents(file)
    origpath = save_orig(file)
    orig_contents = nil
    # We only send back the actual original file contents if the original is
    # a regular file, otherwise we send back an empty string.
    if (origpath =~ /\.ORIG$/ || origpath =~ /\.TMP$/) &&
       File.file?(origpath) && !File.symlink?(origpath)
      orig_contents = IO.read(origpath)
    else
      orig_contents = ''
    end
    orig_contents
  end
  # Save an original copy of the file if that hasn't been done already.
  # save_directory_contents can take three different values:
  #   true:  If the original is a directory then the contents should be
  #          saved by putting them into a tarball
  #   false: If the original is a directory do not save the contents,
  #          just save the metadata of that directory (ownership and perms)
  #   nil:   We haven't yet received a full configuration for the file,
  #          just a request for the original file checksum or contents.
  #          As such we don't know yet what to do with a directory's
  #          contents, nor do we want to save the final version of
  #          non-directories as future setup commands or activity
  #          outside of etch might create or change the original file
  #          before etch is configured to change it.  I.e. we save an
  #          original file the first time etch changes that particular
  #          file, not the first time etch runs on the box.
  # Return the path to that original copy.
  def save_orig(file, save_directory_contents=nil)
    origpathbase = File.join(@origbase, file)
    origpath = nil
    tmporigpath = "#{origpathbase}.TMP"

    if File.exist?("#{origpathbase}.ORIG") ||
       File.symlink?("#{origpathbase}.ORIG")
      origpath = "#{origpathbase}.ORIG"
    elsif File.exist?("#{origpathbase}.NOORIG")
      origpath = "#{origpathbase}.NOORIG"
    elsif File.exist?("#{origpathbase}.TAR")
      origpath = "#{origpathbase}.TAR"
    else
      # The original file has not yet been saved
      first_update = true
    
      # Make sure the directory tree for this file exists in the
      # directory we save originals in.
      origdir = File.dirname(origpathbase)
      if !File.directory?(origdir)
        puts "Making directory tree #{origdir}"
        FileUtils.mkpath(origdir) if (!@dryrun)
      end

      # If we're going to be using a temporary file clean up any
      # existing one so we don't have to worry about overwriting it.
      if save_directory_contents.nil? &&
         (File.exist?(tmporigpath) || File.symlink?(tmporigpath))
        remove_file(tmporigpath)
      end

      if File.directory?(file) && !File.symlink?(file)
        # The original "file" is a directory
        if save_directory_contents
          # Tar up the original directory
          origpath = "#{origpathbase}.TAR"
          filedir = File.dirname(file)
          filebase = File.basename(file)
          puts "Saving contents of original directory #{file} as #{origpath}"
          system("cd #{filedir} && tar cf #{origpath} #{filebase}") if (!@dryrun)
          # There may be contents in that directory that the
          # user doesn't want exposed.  Without a way to know,
          # the safest thing is to set restrictive permissions
          # on the tar file.
          File.chmod(0400, origpath) if (!@dryrun)
        elsif save_directory_contents.nil?
          # We have a timing issue, in that we generally save original
          # files before we have the configuration for that file.  For
          # directories that's a problem, because we save directories
          # differently depending on whether we're configuring them to
          # remain a directory, or replacing the directory with something
          # else (file or symlink).  So if we don't have a definitive
          # directive on how to save the directory
          # (i.e. save_directory_contents is nil) then just save a
          # placeholder until we do get a definitive directive.
          origpath = tmporigpath
          puts "Creating temporary original placeholder #{origpath} for directory #{file}"
          File.open(origpath, 'w') { |file| } if (!@dryrun)
          first_update = false
        else
          # Just create a directory in the originals repository with
          # ownership and permissions to match the original directory.
          origpath = "#{origpathbase}.ORIG"
          st = File::Stat.new(file)
          puts "Saving ownership/permissions of original directory #{file} as #{origpath}"
          Dir.mkdir(origpath, st.mode) if (!@dryrun)
          begin
            File.chown(st.uid, st.gid, origpath) if (!@dryrun)
          rescue Errno::EPERM
            raise if Process.euid == 0
          end
        end
      elsif File.exist?(file) || File.symlink?(file)
        # The original file exists, and is not a directory
        if save_directory_contents.nil?
          origpath = tmporigpath
          puts "Saving temporary copy of original file:  #{file} -> #{origpath}"
        else
          origpath = "#{origpathbase}.ORIG"
          puts "Saving original file:  #{file} -> #{origpath}"
        end
        filedir = File.dirname(file)
        filebase = File.basename(file)
        recursive_copy_and_rename(filedir, filebase, origpath) if (!@dryrun)
      else
        # If the original doesn't exist, we need to flag that so
        # that we don't try to save our generated file as an
        # original on future runs
        if save_directory_contents.nil?
          origpath = tmporigpath
          puts "Original file #{file} doesn't exist, saving that state temporarily as #{origpath}"
        else
          origpath = "#{origpathbase}.NOORIG"
          puts "Original file #{file} doesn't exist, saving that state permanently as #{origpath}"
        end
        File.open(origpath, 'w') { |file| } if (!@dryrun)
      end

      @first_update[file] = first_update
    end

    # Remove the TMP placeholder if it exists and no longer applies
    if origpath != tmporigpath && File.exists?(tmporigpath)
      puts "Removing old temp orig placeholder #{tmporigpath}" if (@debug)
      remove_file(tmporigpath)
    end

    origpath
  end

  # This subroutine maintains a revision history for the file in @historybase
  def save_history(file)
    histpath = File.join(@historybase, "#{file}.HISTORY")

    # Make sure the directory tree for this file exists in the
    # directory we save history in.
    histdir = File.dirname(histpath)
    if !File.directory?(histdir)
      puts "Making directory tree #{histdir}"
      FileUtils.mkpath(histdir) if (!@dryrun)
    end
    # Make sure the corresponding RCS directory exists as well.
    histrcsdir = File.join(histdir, 'RCS')
    if !File.directory?(histrcsdir)
      puts "Making directory tree #{histrcsdir}"
      FileUtils.mkpath(histrcsdir) if (!@dryrun)
    end

    # If the history log doesn't exist and we didn't just create the
    # original backup, that indicates that the original backup was made
    # previously but the history log was not started at the same time.
    # There are a variety of reasons why this might be the case (the
    # original was saved by a previous version of etch that didn't have
    # the history log feature, or the original was saved manually by
    # someone) but whatever the reason is we want to use the original
    # backup to start the history log before updating the history log
    # with the current file.
    if !File.exist?(histpath) && !@first_update[file]
      origpath = save_orig(file)
      if File.file?(origpath) && !File.symlink?(origpath)
        puts "Starting history log with saved original file:  " +
          "#{origpath} -> #{histpath}"
        FileUtils.copy(origpath, histpath) if (!@dryrun)
      else
        puts "Starting history log with 'ls -ld' output for " +
          "saved original file:  #{origpath} -> #{histpath}"
        system("ls -ld #{origpath} > #{histpath} 2>&1") if (!@dryrun)
      end
      # Check the newly created history file into RCS
      histbase = File.basename(histpath)
      puts "Checking initial history log into RCS:  #{histpath}"
      if !@dryrun
        # The -m flag shouldn't be needed, but it won't hurt
        # anything and if something is out of sync and an RCS file
        # already exists it will prevent ci from going interactive.
        system(
          "cd #{histdir} && " +
          "ci -q -t-'Original of an etch modified file' " +
          "-m'Update of an etch modified file' #{histbase} && " +
          "co -q -r -kb #{histbase}")
      end
      set_history_permissions(file)
    end
  
    # Copy current file

    # If the file already exists in RCS we need to check out a locked
    # copy before updating it
    histbase = File.basename(histpath)
    rcsstatus = false
    if !@dryrun
      rcsstatus = system("cd #{histdir} && rlog -R #{histbase} > /dev/null 2>&1")
    end
    if rcsstatus
      # set_history_permissions may set the checked-out file
      # writeable, which normally causes co to abort.  Thus the -f
      # flag.
      system("cd #{histdir} && co -q -l -f #{histbase}") if !@dryrun
    end

    if File.file?(file) && !File.symlink?(file)
      puts "Updating history log:  #{file} -> #{histpath}"
      FileUtils.copy(file, histpath) if (!@dryrun)
    else
      puts "Updating history log with 'ls -ld' output:  " +
        "#{histpath}"
      system("ls -ld #{file} > #{histpath} 2>&1") if (!@dryrun)
    end

    # Check the history file into RCS
    puts "Checking history log update into RCS:  #{histpath}"
    if !@dryrun
      # We only need one of the -t or -m flags depending on whether
      # the history log already exists or not, rather than try to
      # keep track of which one we need just specify both and let RCS
      # pick the one it needs.
      system(
        "cd #{histdir} && " +
        "ci -q -t-'Original of an etch modified file' " +
        "-m'Update of an etch modified file' #{histbase} && " +
        "co -q -r -kb #{histbase}")
    end

    set_history_permissions(file)
  end

  # Ensures that the history log file has appropriate permissions to avoid
  # leaking information.
  def set_history_permissions(file)
    origpath = File.join(@origbase, "#{file}.ORIG")
    histpath = File.join(@historybase, "#{file}.HISTORY")

    # We set the permissions to the more restrictive of the original
    # file permissions and the current file permissions.
    origperms = 0777
    if File.exist?(origpath)
      st = File.lstat(origpath)
      # Mask off the file type
      origperms = st.mode & 07777
    end
    fileperms = 0777
    if File.exist?(file)
      st = File.lstat(file)
      # Mask off the file type
      fileperms = st.mode & 07777
    end

    histperms = origperms & fileperms

    File.chmod(histperms, histpath) if (!@dryrun)

    # Set the permissions on the RCS file too
    histbase = File.basename(histpath)
    histdir = File.dirname(histpath)
    histrcsdir = "#{histdir}/RCS"
    histrcspath = "#{histrcsdir}/#{histbase},v"
    File.chmod(histperms, histrcspath) if (!@dryrun)
  end
  
  def get_local_requests(file)
    requestdir = File.join(@requestbase, file)
    requestlist = []
    if File.directory?(requestdir)
      Dir.foreach(requestdir) do |entry|
        next if entry == '.'
        next if entry == '..'
        requestfile = File.join(requestdir, entry)
        request = IO.read(requestfile)
        # Make sure it is valid XML
        begin
          request_xml = REXML::Document.new(request)
        rescue REXML::ParseException => e
          warn "Local request file #{requestfile} is not valid XML and will be ignored:\n" + e.message
          next
        end
        # Make sure the root element is <request>
        if request_xml.root.name != 'request'
          warn "Local request file #{requestfile} is not properly formatted and will be ignored, XML root element is not <request>"
          next
        end
        # Add it to the queue
        requestlist << request
      end
    end
    requests = nil
    if !requestlist.empty?
      requests = "<requests>\n#{requestlist.join('')}\n</requests>"
    end
    requests
  end
  
  # Haven't found a Ruby method for creating temporary directories,
  # so create a temporary file and replace it with a directory.
  def tempdir(file)
    filebase = File.basename(file)
    filedir = File.dirname(file)
    tmpfile = Tempfile.new(filebase, filedir)
    tmpdir = tmpfile.path
    tmpfile.close!
    Dir.mkdir(tmpdir)
    tmpdir
  end

  def make_backup(file)
    backup = nil
    filebase = File.basename(file)
    filedir = File.dirname(file)
    if !@dryrun
      backup = tempdir(file)
    else
      # Use a fake placeholder name for use in dry run/debug messages
      backup = "#{file}.XXXX"
    end

    backuppath = File.join(backup, filebase)

    puts "Making backup:  #{file} -> #{backuppath}"
    if !@dryrun
      if File.exist?(file) || File.symlink?(file)
        recursive_copy(filedir, filebase, backup)
      else
        # If there's no file to back up then leave a marker file so
        # that restore_backup does the right thing
        File.open("#{backuppath}.NOORIG", "w") { |file| }
      end
    end

    backup
  end

  def restore_backup(file, backup)
    filebase = File.basename(file)
    backuppath = File.join(backup, filebase)

    puts "Restoring #{backuppath} to #{file}"
    if !@dryrun
      # Clean up whatever we wrote out that caused the test to fail
      remove_file(file)

      # Then restore the backup
      if File.exist?(backuppath) || File.symlink?(backuppath)
        File.rename(backuppath, file)
        remove_file(backup)
      elsif File.exist?("#{backuppath}.NOORIG")
        # There was no original file, so we don't need to do
        # anything except remove our NOORIG marker file
        remove_file(backup)
      else
        raise "No backup found in #{backup} to restore to #{file}"
      end
    end
  end

  def process_setup(file, config)
    exectype = 'setup'
    # Because the setup commands are processed every time etch runs
    # (rather than just when the file has changed, as with pre/post) we
    # don't want to print a message for them unless we're in debug mode.
    puts "Processing #{exectype} commands" if (@debug)
    config.elements.each("/config/#{exectype}/exec") do |setup|
      r = process_exec(exectype, setup.text, file)
      # process_exec currently raises an exception if a setup or pre command
      # fails.  In case that ever changes make sure we propagate
      # the error.
      return r if (!r)
    end
  end
  def process_pre(file, config)
    exectype = 'pre'
    puts "Processing #{exectype} commands"
    config.elements.each("/config/#{exectype}/exec") do |pre|
      r = process_exec(exectype, pre.text, file)
      # process_exec currently raises an exception if a setup or pre command
      # fails.  In case that ever changes make sure we propagate
      # the error.
      return r if (!r)
    end
  end
  def process_post(file, config)
    exectype = 'post'
    execs = []
    puts "Processing #{exectype} commands"

    # Add the "exec once" items into the list of commands to process
    # if this is the first time etch has updated this file, and if
    # we haven't already run the command.
    if @first_update[file]
      config.elements.each("/config/#{exectype}/exec_once") do |exec_once|
        if !@exec_already_processed.has_key?(exec_once.text)
          execs << exec_once.text
          @exec_already_processed[exec_once] = true
        else
          puts "Skipping '#{exec_once.text}', it has already " +
            "been executed once this run" if (@debug)
        end
      end
    end

    # Add in the regular exec items as well
    config.elements.each("/config/#{exectype}/exec") do |exec|
      execs << exec.text
    end
  
    # post failures are considered non-fatal, so we ignore the
    # return value from process_exec (it takes care of warning
    # the user).
    execs.each { |exec| process_exec(exectype, exec, file) }
  
    config.elements.each("/config/#{exectype}/exec_once_per_run") do |eopr|
      # Stuff the "exec once per run" nodes into the global hash to
      # be run after we've processed all files.
      puts "Adding '#{eopr.text}' to 'exec once per run' list" if (@debug)
      @exec_once_per_run[eopr.text] = true
    end
  end
  def process_test_before_post(file, config)
    exectype = 'test_before_post'
    puts "Processing #{exectype} commands"
    config.elements.each("/config/#{exectype}/exec") do |test_before_post|
      r = process_exec(exectype, test_before_post.text, file)
      # If the test failed we need to propagate that error
      return r if (!r)
    end
  end
  def process_test(file, config)
    exectype = 'test'
    puts "Processing #{exectype} commands"
    config.elements.each("/config/#{exectype}/exec") do |test|
      r = process_exec(exectype, test.text, file)
      # If the test failed we need to propagate that error
      return r if (!r)
    end
  end
  def process_guard(guard, commandname)
    exectype = 'guard'
    # Because the guard commands are processed every time etch runs we don't
    # want to print a message for them unless we're in debug mode.
    puts "Processing #{exectype}" if (@debug)
    process_exec(exectype, guard, commandname)
  end
  def process_command(command, commandname)
    exectype = 'command'
    puts "Processing #{exectype}"
    process_exec(exectype, command, commandname)
  end
  
  def process_exec(exectype, exec, file='')
    r = true

    # Because the setup and guard commands are processed every time (rather
    # than just when the file has changed as with pre/post) we don't want to
    # print a message for them.
    puts "  Executing '#{exec}'" if ((exectype != 'setup' && exectype != 'guard') || @debug)

    # Actually run the command unless we're in a dry run, or if we're in
    # a damp run and the command is a setup command.
    if ! @dryrun || (@dryrun == 'damp' && exectype == 'setup')
      etch_priority = nil

      if exectype == 'post' || exectype == 'command'
        # Etch is likely running at a lower priority than normal.
        # However, we don't want to run post commands at that
        # priority.  If they restart processes (for example,
        # restarting sshd) the restarted process will be left
        # running at that same lower priority.  sshd is particularly
        # nefarious, because further commands started by users via
        # that low priority sshd will also run at low priority.
        etch_priority = Process.getpriority(Process::PRIO_PROCESS, 0)
        if etch_priority != 0
          puts "  Etch is running at priority #{etch_priority}, " +
               "temporarily adjusting priority to 0 to run #{exectype} command" if (@debug)
          Process.setpriority(Process::PRIO_PROCESS, 0, 0)
        end
      end

      r = system(exec)

      if exectype == 'post' || exectype == 'command'
        if etch_priority != 0
          puts "  Returning priority to #{etch_priority}" if (@debug)
          Process.setpriority(Process::PRIO_USER, 0, etch_priority)
        end
      end
    end

    # If the command exited with error
    if !r
      # We don't normally print the command we're executing for setup and
      # guard commands (see above).  But that makes it hard to figure out
      # what's going on if it fails.  So include the command in the message if
      # there was a failure.
      execmsg = ''
      execmsg = "'#{exec}' " if (exectype == 'setup' || exectype == 'guard')

      # Normally we include the filename of the file that this command
      # is associated with in the messages we print.  But for "exec once
      # per run" commands that doesn't apply.  Assemble a variable
      # that has the filename if we have it, to be included in the
      # error message we're going to print.
      filemsg = ''
      filemsg = "for #{file} " if (!file.empty?)

      # Setup and pre commands are almost always used to install
      # software prerequisites, and bad things generally happen if
      # those software installs fail.  So consider it a fatal error if
      # that occurs.
      if exectype == 'setup' || exectype == 'pre'
        raise "    Setup/Pre command " + execmsg + filemsg +
          "exited with non-zero value"
      # Post commands are generally used to restart services.  While
      # it is unfortunate if they fail, there is little to be gained
      # by having etch exit if they do so.  So simply warn if a post
      # command fails.
      elsif exectype == 'post'
        puts "    Post command " + execmsg + filemsg +
          "exited with non-zero value"
      # process_commands takes the appropriate action when guards and commands
      # fail, so we just warn of any failures here.
      elsif exectype == 'guard'
        puts "    Guard " + execmsg + filemsg + "exited with non-zero value"
      elsif exectype == 'command'
        puts "    Command " + execmsg + filemsg + "exited with non-zero value"
      # For test commands we need to warn the user and then return a
      # value indicating the failure so that a rollback can be
      # performed.
      elsif exectype =~ /^test/
        puts "    Test command " + execmsg + filemsg +
          "exited with non-zero value"
      end
    end

    r
  end

  def lookup_uid(user)
    uid = nil
    if user =~ /^\d+$/
      # If the user was specified as a numeric UID, use it directly.
      uid = user
    else
      # Otherwise attempt to look up the username to get a UID.
      # Default to UID 0 if the username can't be found.
      begin
        pw = Etc.getpwnam(user)
        uid = pw.uid
      rescue ArgumentError
        puts "config.xml requests user #{user}, but that user can't be found.  Using UID 0."
        uid = 0
      end
    end

    uid.to_i
  end

  def lookup_gid(group)
    gid = nil
    if group =~ /^\d+$/
      # If the group was specified as a numeric GID, use it directly.
      gid = group
    else
      # Otherwise attempt to look up the group to get a GID.  Default
      # to GID 0 if the group can't be found.
      begin
        gr = Etc.getgrnam(group)
        gid = gr.gid
      rescue ArgumentError
        puts "config.xml requests group #{group}, but that group can't be found.  Using GID 0."
        gid = 0
      end
    end

    gid.to_i
  end

  # Returns false if the permissions of the given file match the given
  # permissions, true otherwise.
  def compare_permissions(file, perms)
    if ! File.exist?(file)
      return true
    end

    st = File.lstat(file)
    # Mask off the file type
    fileperms = st.mode & 07777
    if perms == fileperms
      return false
    else
      return true
    end
  end

  # Returns false if the ownership of the given file match the given UID
  # and GID, true otherwise.
  def compare_ownership(file, uid, gid)
    if ! File.exist?(file)
      return true
    end

    st = File.lstat(file)
    if st.uid == uid && st.gid == gid
      return false
    else
      return true
    end
  end

  def get_user_confirmation
    while true
      print "Proceed/Skip/Quit? [p|s|q] "
      response = $stdin.gets.chomp
      if response == 'p'
        return CONFIRM_PROCEED
      elsif response == 's'
        return CONFIRM_SKIP
      elsif response == 'q'
        return CONFIRM_QUIT
      end
    end
  end

  def remove_file(file)
    if ! File.exist?(file) && ! File.symlink?(file)
      puts "remove_file: #{file} doesn't exist" if (@debug)
    else
      # The secure delete mechanism doesn't seem to work consistently
      # when not root (in the ever-so-helpful way of not actually
      # removing the file and not indicating any error)
      if Process.euid == 0
        FileUtils.rmtree(file, :secure => true)
      else
        FileUtils.rmtree(file)
      end
    end
  end

  def recursive_copy(sourcedir, sourcefile, destdir)
    # Note that cp -p will follow symlinks.  GNU cp has a -d option to
    # prevent that, but Solaris cp does not, so we resort to cpio.
    # GNU cpio has a --quiet option, but Solaris cpio does not.  Sigh.
    system("cd #{sourcedir} && find #{sourcefile} | cpio -pdum #{destdir}") or
      raise "Copy #{sourcedir}/#{sourcefile} to #{destdir} failed"
  end
  def recursive_copy_and_rename(sourcedir, sourcefile, destname)
    tmpdir = tempdir(destname)
    recursive_copy(sourcedir, sourcefile, tmpdir)
    File.rename(File.join(tmpdir, sourcefile), destname)
    Dir.delete(tmpdir)
  end

  def lock_file(file)
    lockpath = File.join(@lockbase, "#{file}.LOCK")

    # Make sure the directory tree for this file exists in the
    # lock directory
    lockdir = File.dirname(lockpath)
    if ! File.directory?(lockdir)
      puts "Making directory tree #{lockdir}" if (@debug)
      FileUtils.mkpath(lockdir) if (!@dryrun)
    end

    return if (@dryrun)

    # Make 30 attempts (1s sleep after each attempt)
    30.times do |i|
      begin
        fd = IO::sysopen(lockpath, Fcntl::O_WRONLY|Fcntl::O_CREAT|Fcntl::O_EXCL)
        puts "Lock acquired for #{file}" if (@debug)
        f = IO.open(fd) { |f| f.puts $$ }
        @locked_files[file] = true
        return
      rescue Errno::EEXIST
        puts "Attempt to acquire lock for #{file} failed, sleeping 1s"
        sleep 1
      end
    end

    raise "Unable to acquire lock for #{file} after repeated attempts"
  end

  def unlock_file(file)
    lockpath = File.join(@lockbase, "#{file}.LOCK")

    # Since we don't create lock files in dry run mode the rest of this
    # method won't behave properly
    return if (@dryrun)

    if File.exist?(lockpath)
      pid = nil
      File.open(lockpath) { |f| pid = f.gets.chomp.to_i }
      if pid == $$
        puts "Unlocking #{file}" if (@debug)
        File.delete(lockpath)
        @locked_files.delete(file)
      else
        # This shouldn't happen, if it does it's a bug
        raise "Process #{Process.pid} asked to unlock #{file} which is locked by another process (pid #{pid})"
      end
    else
      # This shouldn't happen either
      warn "Lock for #{file} lost"
      @locked_files.delete(file)
    end
  end

  def unlock_all_files
    @locked_files.each_key { |file| unlock_file(file) }
  end
  
  # Any etch lockfiles more than a couple hours old are most likely stale
  # and can be removed.  If told to force we remove all lockfiles.
  def remove_stale_lock_files
    twohoursago = Time.at(Time.now - 60 * 60 * 2)
    Find.find(@lockbase) do |file|
      next unless file =~ /\.LOCK$/
      next unless File.file?(file)

      if @lockforce || File.mtime(file) < twohoursago
        puts "Removing stale lock file #{file}"
        File.delete(file)
      end
    end
  end
  
  def reset_already_processed
    @already_processed.clear
  end
  
  # We limit capturing to 5 minutes.  That should be plenty of time
  # for etch to handle any given file, including running any
  # setup/pre/post commands.
  OUTPUT_CAPTURE_TIMEOUT = 5 * 60
  def start_output_capture
    # Establish a pipe, spawn a child process, and redirect stdout/stderr
    # to the pipe.  The child gathers up anything sent over the pipe and
    # when we close the pipe later it sends the captured output back to us
    # over a second pipe.
    pread, pwrite = IO.pipe
    oread, owrite = IO.pipe
    if fork
      # Parent
      pread.close
      owrite.close
      # Can't use $stdout and $stderr here, child processes don't
      # inherit them and process() spawns a variety of child
      # processes which have output we want to capture.
      oldstdout = STDOUT.dup
      oldstderr = STDERR.dup
      STDOUT.reopen(pwrite)
      STDERR.reopen(pwrite)
      pwrite.close
      @output_pipes << [oread, oldstdout, oldstderr]
    else
      # Child
      # We need to catch any exceptions in the child because the parent
      # might spawn this process in the context of a begin block (in fact
      # it does at the time of this writing), in which case if we throw an
      # exception here execution will jump back to that block, therefore not
      # exiting the child where we want but rather making a big mess of
      # things by continuing to execute the main body of code in parallel
      # with the parent process.
      begin
        pwrite.close
        oread.close
        # If we're somewhere past the first level of the recursion in
        # processing files the stdout/stderr we inherit from our parent will
        # actually be a pipe to the previous file's child process.  We want
        # every child process to talk directly to the real filehandles,
        # otherwise every file that has dependencies will end up with the
        # output for those dependencies gathered with its output.
        STDOUT.reopen(ORIG_STDOUT)
        STDERR.reopen(ORIG_STDERR)
        # stdout is line buffered by default, so if we didn't enable sync here
        # then we wouldn't see the output of the putc below until we output a
        # newline.
        $stdout.sync = true
        output = ''
        begin
          # A surprising number of apps that we restart are ill-behaved and do
          # not properly close stdin/stdout/stderr. With etch's output
          # capturing feature this results in etch hanging around forever
          # waiting for the pipes to close. We time out after a suitable
          # period of time so that etch processes don't hang around forever.
          Timeout.timeout(OUTPUT_CAPTURE_TIMEOUT) do
            while char = pread.getc
              putc(char)
              output << char.chr
            end
          end
        rescue Timeout::Error
          $stderr.puts "Timeout in output capture, some app restarted via post probably didn't daemonize properly"
        end
        pread.close
        owrite.write(output)
        owrite.close
      rescue Exception => e
        $stderr.puts "Exception in output capture child: " + e.message
        $stderr.puts e.backtrace.join("\n") if @debug
      end
      # Exit in such a way that we don't trigger any signal handlers that
      # we might have inherited from the parent process
      exit!
    end
  end
  def stop_output_capture
    oread, oldstdout, oldstderr = @output_pipes.pop
    # The reopen and close closes the parent's end of the pipe to the child
    STDOUT.reopen(oldstdout)
    STDERR.reopen(oldstderr)
    oldstdout.close
    oldstderr.close
    # Which triggers the child to send us the gathered output over the
    # second pipe
    output = oread.read
    oread.close
    # And then the child exits
    Process.wait
    output
  end
  
  def get_private_key_path
    key = nil
    PRIVATE_KEY_PATHS.each do |path|
      if File.readable?(path)
        key = path
        break
      end
    end
    if !key
      warn "No readable private key found, messages to server will not be signed and may be rejected depending on server configuration"
    end
    key
  end
  
  # This method takes in a Net::HTTP::Post and a path to a private key.
  # It will insert a 'timestamp' parameter to the post body, hash the body of
  # the post, sign the hash using the private key, and insert that signature
  # in the HTTP Authorization header field in the post.
  def sign_post!(post, key)
    if key
      post.body << "&timestamp=#{CGI.escape(Time.now.to_s)}"
      private_key = OpenSSL::PKey::RSA.new(File.read(key))
      hashed_body = Digest::SHA1.hexdigest(post.body)
      signature = Base64.encode64(private_key.private_encrypt(hashed_body))
      # encode64 breaks lines at 60 characters with newlines.  Having newlines
      # in an HTTP header screws things up (the lines get interpreted as
      # separate headers) so strip them out.  The Base64 standards seem to
      # generally have a limit on line length, but Ruby's decode64 doesn't
      # seem to complain.  If it ever becomes a problem the server could
      # rebreak the lines.
      signature.gsub!("\n", '')
      post['Authorization'] = "EtchSignature #{signature}"
    end
  end
end

