require 'find'        # Find.find
require 'pathname'    # absolute?
require 'digest/sha1' # hexdigest
require 'base64'      # decode64, encode64
require 'fileutils'   # mkdir_p
require 'erb'
require 'versiontype' # Version
require 'logger'

class Etch
  def self.xmllib
    @@xmllib
  end
  def self.xmllib=(lib)
    @@xmllib=lib
  end
end

# By default we try to use libxml, falling back to rexml if it is not
# available.  The xmllib environment variable can be used to force one library
# or the other, mostly for testing purposes.
begin
  if !ENV['xmllib'] || ENV['xmllib'] == 'libxml'
    require 'rubygems'  # libxml is a gem
    require 'libxml'
    Etch.xmllib = :libxml
  elsif ENV['xmllib'] == 'nokogiri'
    require 'rubygems'  # nokogiri is a gem
    require 'nokogiri'
    Etch.xmllib = :nokogiri
  else
    raise LoadError
  end
rescue LoadError
  if !ENV['xmllib'] || ENV['xmllib'] == 'rexml'
    require 'rexml/document'
    Etch.xmllib = :rexml
  else
    raise
  end
end

class Etch
  # FIXME: I'm not really proud of this, it seems like there ought to be a way
  # to just use one logger.  The problem is that on the server we'd like to
  # use RAILS_DEFAULT_LOGGER for general logging (which is logging to
  # log/production.log), but be able to turn on debug-level logging for
  # individual connections (via the debug parameter sent in the HTTP
  # requests).  If we twiddle the log level of RAILS_DEFAULT_LOGGER then all
  # connections coming in at the same time as the debug connection will also
  # get logged as debug, making the logs confusing.  And if the debug
  # connection aborts for some reason we also risk leaving
  # RAILS_DEFAULT_LOGGER set to debug, flooding the logs.  So it seems like we
  # need a seperate logger for debugging.  But that just seems wrong somehow. 
  # We don't want to just dup RAILS_DEFAULT_LOGGER for each connection, even
  # if Logger didn't immediately blow up we'd probably end up with scrambled
  # logs as simultaneous connections tried to write at the same time.  Or
  # maybe that would work, depending on how Ruby and the OS buffer writes to
  # the file?
  def initialize(logger, debug_logger)
    @logger = logger
    @dlogger = debug_logger
  end
  
  # configdir: Directory containing etch configuration
  # facts: facts in the form of Facter.to_hash
  # request: hash with keys of :files and/or :commands
  #          :files => {'/etc/motd' => {:orig => '/path/to/orig', :local_requests => requestdata}}
  #          :commands => {'packages' => {}, 'solaris_ldapclient' => {}}
  #          If the request hash is empty all items are generated and returned.
  def generate(configdir, facts, request={})
    @configdir = configdir
    @facts = facts
    @request = request
    @fqdn = @facts['fqdn']

    if !@fqdn
      raise "fqdn fact not supplied"
    end

    if !File.directory?(@configdir)
      raise "Config directory #{@configdir} doesn't exist"
    end
    
    # Set up all the variables that point to various directories within our
    # base directory.
    @sourcebase        = "#{@configdir}/source"
    @commandsbase      = "#{@configdir}/commands"
    @sitelibbase       = "#{@configdir}/sitelibs"
    @config_dtd_file   = "#{@configdir}/config.dtd"
    @commands_dtd_file = "#{@configdir}/commands.dtd"
    @defaults_file     = "#{@configdir}/defaults.xml"
    @nodes_file        = "#{@configdir}/nodes.xml"
    @nodegroups_file   = "#{@configdir}/nodegroups.xml"
    
    #
    # Load the DTD which is used to validate config.xml files
    #
    
    @config_dtd = Etch.xmlloaddtd(@config_dtd_file)
    @commands_dtd = Etch.xmlloaddtd(@commands_dtd_file)
    
    #
    # Load the defaults.xml file which sets defaults for parameters that the
    # users don't specify in their config.xml files.
    #
    
    @defaults_xml = Etch.xmlload(@defaults_file)
    
    #
    # Load the nodes file
    #

    @nodes_xml = Etch.xmlload(@nodes_file)
    # Extract the groups for this node
    thisnodeelem = Etch.xmlfindfirst(@nodes_xml, "/nodes/node[@name='#{@fqdn}']")
    groupshash = {}
    if thisnodeelem
      Etch.xmleach(thisnodeelem, 'group') { |group| groupshash[Etch.xmltext(group)] = true }
    else
      @logger.warn "No entry found for node #{@fqdn} in nodes.xml"
      # Some folks might want to terminate here
      #raise "No entry found for node #{@fqdn} in nodes.xml"
    end
    @dlogger.debug "Native groups for node #{@fqdn}: #{groupshash.keys.sort.join(',')}"

    #
    # Load the node groups file
    #

    @nodegroups_xml = Etch.xmlload(@nodegroups_file)

    # Extract the node group hierarchy into a hash for easy reference
    @group_hierarchy = {}
    Etch.xmleach(@nodegroups_xml, '/nodegroups/nodegroup') do |parent|
      Etch.xmleach(parent, 'child') do |child|
        @group_hierarchy[Etch.xmltext(child)] = [] if !@group_hierarchy[Etch.xmltext(child)]
        @group_hierarchy[Etch.xmltext(child)] << parent.attributes['name']
      end
    end

    # Fill out the list of groups for this node with any parent groups
    parentshash = {}
    groupshash.keys.each do |group|
      parents = get_parent_nodegroups(group)
      parents.each { |parent| parentshash[parent] = true }
    end
    parentshash.keys.each { |parent| groupshash[parent] = true }
    @dlogger.debug "Added groups for node #{@fqdn} due to node group hierarchy: #{parentshash.keys.sort.join(',')}"

    # Run the external node grouper
    externalhash = {}
    IO.popen(File.join(@configdir, 'nodegrouper') + ' ' + @fqdn) do |pipe|
      pipe.each { |group| externalhash[group.chomp] = true }
    end
    if !$?.success?
      raise "External node grouper exited with error #{$?.exitstatus}"
    end
    externalhash.keys.each { |external| groupshash[external] = true }
    @dlogger.debug "Added groups for node #{@fqdn} due to external node grouper: #{externalhash.keys.sort.join(',')}"

    @groups = groupshash.keys.sort
    @dlogger.debug "Total groups for node #{@fqdn}: #{@groups.join(',')}"

    #
    # Build up a list of files to generate, either from the request or from
    # the source repository if the request is for all files
    #

    filelist = []
    if request.empty?
      @dlogger.debug "Building complete file list for request from #{@fqdn}"
      Find.find(@sourcebase) do |path|
        if File.directory?(path) && File.exist?(File.join(path, 'config.xml'))
          # Strip @sourcebase from start of path
          filelist << path.sub(Regexp.new('^' + Regexp.escape(@sourcebase)), '')
        end
      end
    elsif request[:files]
      @dlogger.debug "Building file list based on request for specific files from #{@fqdn}"
      filelist = request[:files].keys
    end
    @dlogger.debug "Generating #{filelist.length} files"

    #
    # Loop over each file in the request and generate it
    #
  
    @filestack = {}
    @already_generated = {}
    @generation_status = {}
    @configs = {}
    @need_orig = {}
    @allcommands = {}
    @retrycommands = {}
    
    filelist.each do |file|
      @dlogger.debug "Generating #{file}"
      generate_file(file, request)
    end
    
    #
    # Generate configuration commands
    #
    
    commandnames = []
    if request.empty?
      @dlogger.debug "Building complete configuration commands for request from #{@fqdn}"
      Find.find(@commandsbase) do |path|
        if File.directory?(path) && File.exist?(File.join(path, 'commands.xml'))
          commandnames << File.basename(path)
        end
      end
    elsif request[:commands]
      @dlogger.debug "Building commands based on request for specific commands from #{@fqdn}"
      commandnames = request[:commands].keys
    end
    @dlogger.debug "Generating #{commandnames.length} commands"
    commandnames.each do |commandname|
      @dlogger.debug "Generating command #{commandname}"
      generate_commands(commandname, request)
    end
    
    #
    # Returned our assembled results
    #
    
    {:configs => @configs,
     :need_orig => @need_orig,
     :allcommands => @allcommands,
     :retrycommands => @retrycommands}
  end

  #
  # Private subroutines
  #
  private

  # Recursive method to get all of the parents of a node group
  def get_parent_nodegroups(group)
    parentshash = {}
    if @group_hierarchy[group]
      @group_hierarchy[group].each do |parent|
        parentshash[parent] = true
        grandparents = get_parent_nodegroups(parent)
        grandparents.each { |gp| parentshash[gp] = true }
      end
    end
    parentshash.keys.sort
  end
  
  # Returns the value of the generation_status variable, see comments in
  # method for possible values.
  def generate_file(file, request)
    # Skip files we've already generated in response to <depend>
    # statements.
    if @already_generated[file]
      @dlogger.debug "Skipping already generated #{file}"
      # Return the status of that previous generation
      return @generation_status[file]
    end

    # Check for circular dependencies, otherwise we're vulnerable
    # to going into an infinite loop
    if @filestack[file]
      raise "Circular dependency detected for #{file}"
    end
    @filestack[file] = true
    
    config_xml_file = File.join(@sourcebase, file, 'config.xml')
    if !File.exist?(config_xml_file)
      raise "config.xml for #{file} does not exist"
    end
    
    # Load the config.xml file
    config_xml = Etch.xmlload(config_xml_file)
    
    # Filter the config.xml file by looking for attributes
    begin
      configfilter!(Etch.xmlroot(config_xml))
    rescue Exception => e
      raise Etch.wrap_exception(e, "Error filtering config.xml for #{file}:\n" + e.message)
    end
    
    # Validate the filtered file against config.dtd
    begin
      Etch.xmlvalidate(config_xml, @config_dtd)
    rescue Exception => e
      raise Etch.wrap_exception(e, "Filtered config.xml for #{file} fails validation:\n" + e.message)
    end
    
    generation_status = :unknown
    # As we go through the process of generating the file we'll end up with
    # four possible outcomes:
    # fatal error: raise an exception
    # failure: we're missing needed data for this file or a dependency,
    #          generally the original file
    # success: we successfully processed a valid configuration
    # unknown: no valid configuration nor errors encountered, probably because
    #          filtering removed everything from the config.xml file.  This
    #          should be considered a successful outcome, it indicates the
    #          caller/client provided us with all required data and our result
    #          is that no action needs to be taken.
    # We keep track of which of the failure, success or unknown states we end
    # up in via the generation_status variable.  We initialize it to :unknown.
    # If we encounter either failure or success we set it to false or :success.
    catch :generate_done do
      # Generate any other files that this file depends on
      depends = []
      proceed = true
      Etch.xmleach(config_xml, '/config/depend') do |depend|
        @dlogger.debug "Generating dependency #{Etch.xmltext(depend)}"
        depends << Etch.xmltext(depend)
        r = generate_file(Etch.xmltext(depend), request)
        proceed = proceed && r
      end
      # Also generate any commands that this file depends on
      Etch.xmleach(config_xml, '/config/dependcommand') do |dependcommand|
        @dlogger.debug "Generating command dependency #{Etch.xmltext(dependcommand)}"
        r = generate_commands(Etch.xmltext(dependcommand), request)
        proceed = proceed && r
      end
      
      if !proceed
        @dlogger.debug "One or more dependencies of #{file} need data from client"
      end
      
      # Make sure we have the original contents for this file
      original_file = nil
      if request[:files] && request[:files][file] && request[:files][file][:orig]
        original_file = request[:files][file][:orig]
      else
        @dlogger.debug "Need original contents of #{file} from client"
        proceed = false
      end
      
      if !proceed
        # If any file dependency failed to generate (due to a need for orig
        # contents from the client) then we need to tell the client to request
        # all of the files in the dependency tree again.
        # 
        # For example, we have afile which depends on bfile and cfile.  The
        # user requests afile and bfile on the command line.  The client sends
        # sums for afile and bfile.  The server sees the need for cfile's sum, so
        # it sends back contents for bfile and a sum request for cfile and afile
        # (since afile depends on bfile).  The client sends sums for afile and
        # cfile.  The server sends back contents for cfile, and a sum request for
        # bfile and afile.  This repeats forever as the server isn't smart enough
        # to ask for everything it needs and the client isn't smart enough to send
        # everything.
        depends.each { |depend| @need_orig[depend] = true }
        
        # Tell the client to request this file again
        @need_orig[file] = true
        
        # Strip this file's config down to the bare necessities
        filter_xml_completely!(config_xml, ['depend', 'setup'])
        
        # And hit the eject button
        generation_status = false
        throw :generate_done
      end
      
      # Change into the corresponding directory so that the user can
      # refer to source files and scripts by their relative pathnames.
      Dir::chdir "#{@sourcebase}/#{file}"

      # See what type of action the user has requested

      # Check to see if the user has requested that we revert back to the
      # original file.
      if Etch.xmlfindfirst(config_xml, '/config/revert')
        # Pass the revert action back to the client
        filter_xml!(config_xml, ['revert'])
        generation_status = :success
        throw :generate_done
      end
  
      # Perform any server setup commands
      if Etch.xmlfindfirst(config_xml, '/config/server_setup')
        @dlogger.debug "Processing server setup commands"
        Etch.xmleach(config_xml, '/config/server_setup/exec') do |cmd|
          @dlogger.debug "  Executing #{Etch.xmltext(cmd)}"
          # Explicitly invoke using /bin/sh so that syntax like
          # "FOO=bar myprogram" works.
          success = system('/bin/sh', '-c', Etch.xmltext(cmd))
          if !success
            raise "Server setup command #{Etch.xmltext(cmd)} for file #{file} exited with non-zero value"
          end
        end
      end
    
      # Pull out any local requests
      local_requests = nil
      if request[:files] && request[:files][file] && request[:files][file][:local_requests]
        local_requests = request[:files][file][:local_requests]
      end
    
      #
      # Regular file
      #

      if Etch.xmlfindfirst(config_xml, '/config/file')
        #
        # Assemble the contents for the file
        #
        newcontents = ''
      
        if Etch.xmlfindfirst(config_xml, '/config/file/source/plain')
          plain_elements = Etch.xmlarray(config_xml, '/config/file/source/plain')
          if check_for_inconsistency(plain_elements)
            raise "Inconsistent 'plain' entries for #{file}"
          end
        
          # Just slurp the file in
          plain_file = Etch.xmltext(plain_elements.first)
          newcontents = IO::read(plain_file)
        elsif Etch.xmlfindfirst(config_xml, '/config/file/source/template')
          template_elements = Etch.xmlarray(config_xml, '/config/file/source/template')
          if check_for_inconsistency(template_elements)
            raise "Inconsistent 'template' entries for #{file}"
          end
        
          # Run the template through ERB to generate the file contents
          template = Etch.xmltext(template_elements.first)
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          newcontents = external.process_template(template)
        elsif Etch.xmlfindfirst(config_xml, '/config/file/source/script')
          script_elements = Etch.xmlarray(config_xml, '/config/file/source/script')
          if check_for_inconsistency(script_elements)
            raise "Inconsistent 'script' entries for #{file}"
          end
        
          # Run the script to generate the file contents
          script = Etch.xmltext(script_elements.first)
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          newcontents = external.run_script(script)
        elsif Etch.xmlfindfirst(config_xml, '/config/file/always_manage_metadata')
          # always_manage_metadata is a special case where we proceed
          # even if we don't have any source for file contents.
        else
          # If the filtering has removed the source for this file's
          # contents, that means it doesn't apply to this node.
          @dlogger.debug "No configuration for file #{file} contents, doing nothing"
        
          # This check is unnecessary for the proper functioning of
          # the application, as the next check (for empty contents) is
          # in some senses a superset.  However, the slightly
          # different debug messages (no source for contents, versus
          # empty contents) might help the user.
        end
      
        # If the new contents are empty, and the user hasn't asked us to
        # keep empty files or always manage the metadata, then assume
        # this file is not applicable to this node and do nothing.
        if newcontents == '' &&
            ! Etch.xmlfindfirst(config_xml, '/config/file/allow_empty') &&
            ! Etch.xmlfindfirst(config_xml, '/config/file/always_manage_metadata')
          @dlogger.debug "New contents for file #{file} empty, doing nothing"
        else
          # Finish assembling the file contents as long as we're not
          # proceeding based only on always_manage_metadata.  If we are
          # proceeding based only on always_manage_metadata we want to make
          # sure that the only action we'll take is to manage metadata, not
          # muck with the file's contents.
          if !(newcontents == '' &&
               Etch.xmlfindfirst(config_xml, '/config/file/always_manage_metadata'))
            # Add the warning message (if defined)
            warning_file = nil
            if Etch.xmlfindfirst(config_xml, '/config/file/warning_file')
              if !Etch.xmltext(Etch.xmlfindfirst(config_xml, '/config/file/warning_file')).empty?
                warning_file = Etch.xmltext(Etch.xmlfindfirst(config_xml, '/config/file/warning_file'))
              end
            elsif Etch.xmlfindfirst(@defaults_xml, '/config/file/warning_file')
              if !Etch.xmltext(Etch.xmlfindfirst(@defaults_xml, '/config/file/warning_file')).empty?
                warning_file = Etch.xmltext(Etch.xmlfindfirst(@defaults_xml, '/config/file/warning_file'))
              end
            end
            if warning_file
              warning = ''

              # First the comment opener
              comment_open = nil
              if Etch.xmlfindfirst(config_xml, '/config/file/comment_open')
                comment_open = Etch.xmltext(Etch.xmlfindfirst(config_xml, '/config/file/comment_open'))
              elsif Etch.xmlfindfirst(@defaults_xml, '/config/file/comment_open')
                comment_open = Etch.xmltext(Etch.xmlfindfirst(@defaults_xml, '/config/file/comment_open'))
              end
              if comment_open && !comment_open.empty?
                warning << comment_open << "\n"
              end

              # Then the message
              comment_line = '# '
              if Etch.xmlfindfirst(config_xml, '/config/file/comment_line')
                comment_line = Etch.xmltext(Etch.xmlfindfirst(config_xml, '/config/file/comment_line'))
              elsif Etch.xmlfindfirst(@defaults_xml, '/config/file/comment_line')
                comment_line = Etch.xmltext(Etch.xmlfindfirst(@defaults_xml, '/config/file/comment_line'))
              end

              warnpath = Pathname.new(warning_file)
              if !File.exist?(warning_file) && !warnpath.absolute?
                warning_file = File.expand_path(warning_file, @configdir)
              end

              File.open(warning_file) do |warnfile|
                while line = warnfile.gets
                  warning << comment_line << line
                end
              end

              # And last the comment closer
              comment_close = nil
              if Etch.xmlfindfirst(config_xml, '/config/file/comment_close')
                comment_close = Etch.xmltext(Etch.xmlfindfirst(config_xml, '/config/file/comment_close'))
              elsif Etch.xmlfindfirst(@defaults_xml, '/config/file/comment_close')
                comment_close = Etch.xmltext(Etch.xmlfindfirst(@defaults_xml, '/config/file/comment_close'))
              end
              if comment_close && !comment_close.empty?
                warning << comment_close << "\n"
              end

              # By default we insert the warning at the top of the
              # generated file.  However, some files (particularly
              # scripts) have a special first line.  The user can flag
              # those files to have the warning inserted starting at the
              # second line.
              if !Etch.xmlfindfirst(config_xml, '/config/file/warning_on_second_line')
                # And then other files (notably Solaris crontabs) can't
                # have any blank lines.  Normally we insert a blank
                # line between the warning message and the generated
                # file to improve readability.  The user can flag us to
                # not insert that blank line.
                if !Etch.xmlfindfirst(config_xml, '/config/file/no_space_around_warning')
                  newcontents = warning + "\n" + newcontents
                else
                  newcontents = warning + newcontents
                end
              else
                parts = newcontents.split("\n", 2)
                if !Etch.xmlfindfirst(config_xml, '/config/file/no_space_around_warning')
                  newcontents = parts[0] << "\n\n" << warning << "\n" << parts[1]
                else
                  newcontents = parts[0] << warning << parts[1]
                end
              end
            end # if warning_file
    
            # Add the generated file contents to the XML
            Etch.xmladd(config_xml, '/config/file', 'contents', Base64.encode64(newcontents))
          end

          # Remove the source configuration from the XML, the
          # client won't need to see it
          Etch.xmlremovepath(config_xml, '/config/file/source')

          # Remove all of the warning related elements from the XML, the
          # client won't need to see them
          Etch.xmlremovepath(config_xml, '/config/file/warning_file')
          Etch.xmlremovepath(config_xml, '/config/file/warning_on_second_line')
          Etch.xmlremovepath(config_xml, '/config/file/no_space_around_warning')
          Etch.xmlremovepath(config_xml, '/config/file/comment_open')
          Etch.xmlremovepath(config_xml, '/config/file/comment_line')
          Etch.xmlremovepath(config_xml, '/config/file/comment_close')
        
          # If the XML doesn't contain ownership and permissions entries
          # then add appropriate ones based on the defaults
          if !Etch.xmlfindfirst(config_xml, '/config/file/owner')
            if Etch.xmlfindfirst(@defaults_xml, '/config/file/owner')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/file/owner'),
                Etch.xmlfindfirst(config_xml, '/config/file'))
            else
              raise "defaults.xml needs /config/file/owner"
            end
          end
          if !Etch.xmlfindfirst(config_xml, '/config/file/group')
            if Etch.xmlfindfirst(@defaults_xml, '/config/file/group')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/file/group'),
                Etch.xmlfindfirst(config_xml, '/config/file'))
            else
              raise "defaults.xml needs /config/file/group"
            end
          end
          if !Etch.xmlfindfirst(config_xml, '/config/file/perms')
            if Etch.xmlfindfirst(@defaults_xml, '/config/file/perms')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/file/perms'),
                Etch.xmlfindfirst(config_xml, '/config/file'))
            else
              raise "defaults.xml needs /config/file/perms"
            end
          end
      
          # Send the file contents and metadata to the client
          filter_xml!(config_xml, ['file'])
      
          generation_status = :success
          throw :generate_done
        end
      end

      #
      # Symbolic link
      #
  
      if Etch.xmlfindfirst(config_xml, '/config/link')
        dest = nil
    
        if Etch.xmlfindfirst(config_xml, '/config/link/dest')
          dest_elements = Etch.xmlarray(config_xml, '/config/link/dest')
          if check_for_inconsistency(dest_elements)
            raise "Inconsistent 'dest' entries for #{file}"
          end
      
          dest = Etch.xmltext(dest_elements.first)
        elsif Etch.xmlfindfirst(config_xml, '/config/link/script')
          # The user can specify a script to perform more complex
          # testing to decide whether to create the link or not and
          # what its destination should be.
        
          script_elements = Etch.xmlarray(config_xml, '/config/link/script')
          if check_for_inconsistency(script_elements)
            raise "Inconsistent 'script' entries for #{file}"
          end
        
          script = Etch.xmltext(script_elements.first)
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          dest = external.run_script(script)
        
          # Remove the script element(s) from the XML, the client won't need
          # to see them
          script_elements.each { |se| Etch.xmlremove(config_xml, se) }
        else
          # If the filtering has removed the destination for the link,
          # that means it doesn't apply to this node.
          @dlogger.debug "No configuration for link #{file} destination, doing nothing"
        end

        if !dest || dest.empty?
          @dlogger.debug "Destination for link #{file} empty, doing nothing"
        else
          # If there isn't a dest element in the XML (if the user used a
          # script) then insert one for the benefit of the client
          if !Etch.xmlfindfirst(config_xml, '/config/link/dest')
            Etch.xmladd(config_xml, '/config/link', 'dest', dest)
          end

          # If the XML doesn't contain ownership and permissions entries
          # then add appropriate ones based on the defaults
          if !Etch.xmlfindfirst(config_xml, '/config/link/owner')
            if Etch.xmlfindfirst(@defaults_xml, '/config/link/owner')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/link/owner'),
                Etch.xmlfindfirst(config_xml, '/config/link'))
            else
              raise "defaults.xml needs /config/link/owner"
            end
          end
          if !Etch.xmlfindfirst(config_xml, '/config/link/group')
            if Etch.xmlfindfirst(@defaults_xml, '/config/link/group')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/link/group'),
                Etch.xmlfindfirst(config_xml, '/config/link'))
            else
              raise "defaults.xml needs /config/link/group"
            end
          end
          if !Etch.xmlfindfirst(config_xml, '/config/link/perms')
            if Etch.xmlfindfirst(@defaults_xml, '/config/link/perms')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/link/perms'),
                Etch.xmlfindfirst(config_xml, '/config/link'))
            else
              raise "defaults.xml needs /config/link/perms"
            end
          end
      
          # Send the file contents and metadata to the client
          filter_xml!(config_xml, ['link'])

          generation_status = :success
          throw :generate_done
        end
      end

      #
      # Directory
      #
  
      if Etch.xmlfindfirst(config_xml, '/config/directory')
        create = false
        if Etch.xmlfindfirst(config_xml, '/config/directory/create')
          create = true
        elsif Etch.xmlfindfirst(config_xml, '/config/directory/script')
          # The user can specify a script to perform more complex testing
          # to decide whether to create the directory or not.
          script_elements = Etch.xmlarray(config_xml, '/config/directory/script')
          if check_for_inconsistency(script_elements)
            raise "Inconsistent 'script' entries for #{file}"
          end
        
          script = Etch.xmltext(script_elements.first)
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          create = external.run_script(script)
          create = false if create.empty?
        
          # Remove the script element(s) from the XML, the client won't need
          # to see them
          script_elements.each { |se| Etch.xmlremove(config_xml, se) }
        else
          # If the filtering has removed the directive to create this
          # directory, that means it doesn't apply to this node.
          @dlogger.debug "No configuration to create directory #{file}, doing nothing"
        end
    
        if !create
          @dlogger.debug "Directive to create directory #{file} false, doing nothing"
        else
          # If there isn't a create element in the XML (if the user used a
          # script) then insert one for the benefit of the client
          if !Etch.xmlfindfirst(config_xml, '/config/directory/create')
            Etch.xmladd(config_xml, '/config/directory', 'create', nil)
          end

          # If the XML doesn't contain ownership and permissions entries
          # then add appropriate ones based on the defaults
          if !Etch.xmlfindfirst(config_xml, '/config/directory/owner')
            if Etch.xmlfindfirst(@defaults_xml, '/config/directory/owner')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/directory/owner'),
                Etch.xmlfindfirst(config_xml, '/config/directory'))
            else
              raise "defaults.xml needs /config/directory/owner"
            end
          end
          if !Etch.xmlfindfirst(config_xml, '/config/directory/group')
            if Etch.xmlfindfirst(@defaults_xml, '/config/directory/group')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/directory/group'),
                Etch.xmlfindfirst(config_xml, '/config/directory'))
            else
              raise "defaults.xml needs /config/directory/group"
            end
          end
          if !Etch.xmlfindfirst(config_xml, '/config/directory/perms')
            if Etch.xmlfindfirst(@defaults_xml, '/config/directory/perms')
              Etch.xmlcopyelem(
                Etch.xmlfindfirst(@defaults_xml, '/config/directory/perms'),
                Etch.xmlfindfirst(config_xml, '/config/directory'))
            else
              raise "defaults.xml needs /config/directory/perms"
            end
          end
      
          # Send the file contents and metadata to the client
          filter_xml!(config_xml, ['directory'])
      
          generation_status = :success
          throw :generate_done
        end
      end

      #
      # Delete whatever is there
      #

      if Etch.xmlfindfirst(config_xml, '/config/delete')
        proceed = false
        if Etch.xmlfindfirst(config_xml, '/config/delete/proceed')
          proceed = true
        elsif Etch.xmlfindfirst(config_xml, '/config/delete/script')
          # The user can specify a script to perform more complex testing
          # to decide whether to delete the file or not.
          script_elements = Etch.xmlarray(config_xml, '/config/delete/script')
          if check_for_inconsistency(script_elements)
            raise "Inconsistent 'script' entries for #{file}"
          end
        
          script = Etch.xmltext(script_elements.first)
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          proceed = external.run_script(script)
          proceed = false if proceed.empty?
        
          # Remove the script element(s) from the XML, the client won't need
          # to see them
          script_elements.each { |se| Etch.xmlremove(config_xml, se) }
        else
          # If the filtering has removed the directive to remove this
          # file, that means it doesn't apply to this node.
          @dlogger.debug "No configuration to delete #{file}, doing nothing"
        end
    
        if !proceed
          @dlogger.debug "Directive to delete #{file} false, doing nothing"
        else
          # If there isn't a proceed element in the XML (if the user used a
          # script) then insert one for the benefit of the client
          if !Etch.xmlfindfirst(config_xml, '/config/delete/proceed')
            Etch.xmladd(config_xml, '/config/delete', 'proceed', nil)
          end

          # Send the file contents and metadata to the client
          filter_xml!(config_xml, ['delete'])
      
          generation_status = :success
          throw :generate_done
        end
      end
    end
    
    # In addition to successful configs return configs for files that need
    # orig data (generation_status==false) because any setup commands might be
    # needed to create the original file.
    if generation_status != :unknown &&
       Etch.xmlfindfirst(config_xml, '/config/*')
      # The client needs this attribute to know to which file
      # this chunk of XML refers
      Etch.xmlattradd(Etch.xmlroot(config_xml), 'filename', file)
      @configs[file] = config_xml
    end
  
    @already_generated[file] = true
    @filestack.delete(file)
    @generation_status[file] = generation_status
    
    generation_status
  end
  
  # Returns the value of the generation_status variable, see comments in
  # method for possible values.
  def generate_commands(command, request)
    # Skip commands we've already generated in response to <depend>
    # statements.
    if @already_generated[command]
      @dlogger.debug "Skipping already generated command #{command}"
      return
    end
    
    # Check for circular dependencies, otherwise we're vulnerable
    # to going into an infinite loop
    if @filestack[command]
      raise "Circular dependency detected for command #{command}"
    end
    @filestack[command] = true
    
    commands_xml_file = File.join(@commandsbase, command, 'commands.xml')
    if !File.exist?(commands_xml_file)
      raise "commands.xml for #{command} does not exist"
    end
    
    # Load the commands.xml file
    commands_xml = Etch.xmlload(commands_xml_file)
    
    # Filter the commands.xml file by looking for attributes
    begin
      configfilter!(Etch.xmlroot(commands_xml))
    rescue Exception => e
      raise Etch.wrap_exception(e, "Error filtering commands.xml for #{command}:\n" + e.message)
    end
    
    # Validate the filtered file against commands.dtd
    begin
      Etch.xmlvalidate(commands_xml, @commands_dtd)
    rescue Exception => e
      raise Etch.wrap_exception(e, "Filtered commands.xml for #{command} fails validation:\n" + e.message)
    end
    
    generation_status = :unknown
    # As we go through the process of generating the command we'll end up with
    # four possible outcomes:
    # fatal error: raise an exception
    # failure: we're missing needed data for this command or a dependency,
    #          generally the original file for a file this command depends on
    # success: we successfully processed a valid configuration
    # unknown: no valid configuration nor errors encountered, probably because
    #          filtering removed everything from the commands.xml file.  This
    #          should be considered a successful outcome, it indicates the
    #          caller/client provided us with all required data and our result
    #          is that no action needs to be taken.
    # We keep track of which of the failure, success or unknown states we end
    # up in via the generation_status variable.  We initialize it to :unknown.
    # If we encounter either failure or success we set it to false or :success.
    catch :generate_done do
      # Generate any other commands that this command depends on
      dependfiles = []
      proceed = true
      Etch.xmleach(commands_xml, '/commands/depend') do |depend|
        @dlogger.debug "Generating command dependency #{Etch.xmltext(depend)}"
        r = generate_commands(Etch.xmltext(depend), request)
        proceed = proceed && r
      end
      # Also generate any files that this command depends on
      Etch.xmleach(commands_xml, '/commands/dependfile') do |dependfile|
        @dlogger.debug "Generating file dependency #{Etch.xmltext(dependfile)}"
        dependfiles << Etch.xmltext(dependfile)
        r = generate_file(Etch.xmltext(dependfile), request)
        proceed = proceed && r
      end
      if !proceed
        @dlogger.debug "One or more dependencies of #{command} need data from client"
        # If any file dependency failed to generate (due to a need for orig
        # contents from the client) then we need to tell the client to request
        # all of the files in the dependency tree again.  See the big comment
        # in generate_file for further explanation.
        dependfiles.each { |dependfile| @need_orig[dependfile] = true }
        # Try again next time
        @retrycommands[command] = true
        generation_status = false
        throw :generate_done
      end
      
      # Change into the corresponding directory so that the user can
      # refer to source files and scripts by their relative pathnames.
      Dir::chdir "#{@commandsbase}/#{command}"
      
      # Check that the resulting document is consistent after filtering
      remove = []
      Etch.xmleach(commands_xml, '/commands/step') do |step|
        guard_exec_elements = Etch.xmlarray(step, 'guard/exec')
        if check_for_inconsistency(guard_exec_elements)
          raise "Inconsistent guard 'exec' entries for #{command}: " +
            guard_exec_elements.collect {|elem| Etch.xmltext(elem)}.join(',')
        end
        command_exec_elements = Etch.xmlarray(step, 'command/exec')
        if check_for_inconsistency(command_exec_elements)
          raise "Inconsistent command 'exec' entries for #{command}: " +
            command_exec_elements.collect {|elem| Etch.xmltext(elem)}.join(',')
        end
        # If filtering has removed both the guard and command elements
        # we can remove this step.
        if guard_exec_elements.empty? && command_exec_elements.empty?
          remove << step
        # If filtering has removed the guard but not the command or vice
        # versa that's an error.
        elsif guard_exec_elements.empty?
          raise "Filtering removed guard, but left command: " +
            Etch.xmltext(command_exec_elements.first)
        elsif command_exec_elements.empty?
          raise "Filtering removed command, but left guard: " +
            Etch.xmltext(guard_exec_elements.first)
        end
      end
      remove.each { |elem| Etch.xmlremove(commands_xml, elem) }
      
      # I'm not sure if we'd benefit from further checking the XML for
      # validity.  For now we declare success if we got this far.
      generation_status = :success
    end
    
    # If filtering didn't remove all the content then add this to the list of
    # commands to be returned to the client.
    if generation_status && generation_status != :unknown &&
       Etch.xmlfindfirst(commands_xml, '/commands/*')
      # Include the commands directory name to aid troubleshooting on the
      # client side.
      Etch.xmlattradd(Etch.xmlroot(commands_xml), 'commandname', command)
      @allcommands[command] = commands_xml
    end
    
    @already_generated[command] = true
    @filestack.delete(command)
    @generation_status[command] = generation_status
    
    generation_status
  end
  
  ALWAYS_KEEP = ['depend', 'setup', 'pre', 'test_before_post', 'post', 'test']
  def filter_xml_completely!(config_xml, keepers=[])
    remove = []
    Etch.xmleachall(config_xml) do |elem|
      if !keepers.include?(elem.name)
        remove << elem
      end
    end
    remove.each { |elem| Etch.xmlremove(config_xml, elem) }
    # FIXME: strip comments
  end
  def filter_xml!(config_xml, keepers=[])
    filter_xml_completely!(config_xml, keepers.concat(ALWAYS_KEEP))
  end

  def configfilter!(element)
    elem_remove = []
    Etch.xmleachall(element) do |elem|
      catch :next_element do
        attr_remove = []
        Etch.xmleachattrall(elem) do |attribute|
          if !check_attribute(attribute.name, attribute.value)
            elem_remove << elem
            throw :next_element
          else
            attr_remove << attribute
          end
        end
        attr_remove.each { |attribute| Etch.xmlattrremove(element, attribute) }
        # Then check any children of this element
        configfilter!(elem)
      end
    end
    elem_remove.each { |elem| Etch.xmlremove(element, elem) }
  end

  # Used when parsing each config.xml to filter out any elements which
  # don't match the configuration of this node.  If the attribute matches
  # then we just remove the attribute but leave the element it is attached
  # to.  If the attribute doesn't match then we remove the entire element.
  #
  # Things we'd like to do in the config.xml files:
  # Implemented:
  # - Negation (!)
  # - Numerical comparisons (<, <=, =>, >)
  # - Regular expressions (//)
  # Not yet:
  # - Flow control (if/else)
  def check_attribute(name, value)
    comparables = []
    if name == 'group'
      comparables = @groups
    elsif @facts[name]
      comparables = [@facts[name]]
    end
    
    result = false
    negate = false
    
    # Negation
    # i.e. <plain os="!SunOS"></plain>
    if value =~ /^\!/
      negate = true
      value.sub!(/^\!/, '')  # Strip off the bang
    end
    
    comparables.each do |comp|
      # Numerical comparisons
      # i.e. <plain os="SunOS" osversion=">=5.8"></plain>
      # Note that the standard for XML requires that the < character be
      # escaped in attribute values, so you have to use &lt;
      # That's been decoded by the XML parser before it gets to us
      # here so we don't have to handle it specially
      if value =~ %r{^(<|<=|>=|>)\s*([\d\.]+)$}
        operator = $1
        valueversion = Version.new($2)
        compversion = Version.new(comp)
        if compversion.send(operator.to_sym, valueversion)
          result = true
        end
      # Regular expressions
      # i.e. <plain group="/dns-.*-server/"></plain>
      # or   <plain os="/Red Hat/"></plain>
      elsif value =~ %r{^/(.*)/$}
        regexp = Regexp.new($1)
        if comp =~ regexp
          result = true
        end
      else
        if comp == value
          result = true
        end
      end
    end
    
    if negate
      return !result
    else
      return result
    end
  end
  
  # We let users specify a source multiple times in a config.xml.  This is
  # necessary if multiple groups require the same file, for example.
  # However, the user needs to be consistent.  So this is valid on a
  # machine that is providing both groups:
  #
  # <plain group="foo_server">source_file</plain>
  # <plain group="bar_server">source_file</plain>
  #
  # But this isn't valid on the same machine.  Which of the two files
  # should we use?
  #
  # <plain group="foo_server">source_file</plain>
  # <plain group="bar_server">different_source_file</plain>
  #
  # This subroutine checks a list of XML elements to determine if they all
  # contain the same value.  Returns true if there is inconsistency.
  def check_for_inconsistency(elements)
    elements_as_text = elements.collect { |elem| Etch.xmltext(elem) }
    if elements_as_text.uniq.length > 1
      return true
    else
      return false
    end
  end
  
  # These methods provide an abstraction from the underlying XML library in
  # use, allowing us to use whatever the user has available and switch between
  # libraries easily.
  
  def self.xmlnewdoc
    case Etch.xmllib
    when :libxml
      LibXML::XML::Document.new
    when :nokogiri
      Nokogiri::XML::Document.new
    when :rexml
      REXML::Document.new
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlroot(doc)
    case Etch.xmllib
    when :libxml
      doc.root
    when :nokogiri
      doc.root
    when :rexml
      doc.root
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlsetroot(doc, root)
    case Etch.xmllib
    when :libxml
      doc.root = root
    when :nokogiri
      doc.root = root
    when :rexml
      doc << root
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlload(file)
    case Etch.xmllib
    when :libxml
      LibXML::XML::Document.file(file)
    when :nokogiri
      Nokogiri::XML(File.open(file)) do |config|
        # Nokogiri is tolerant of malformed documents by default.  Good when
        # parsing HTML, but there's no reason for us to tolerate errors.  We
        # want to ensure that the user's instructions to us are clear.
        config.options = Nokogiri::XML::ParseOptions::STRICT
      end
    when :rexml
      REXML::Document.new(File.open(file))
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlloaddtd(dtdfile)
    case Etch.xmllib
    when :libxml
      LibXML::XML::Dtd.new(IO.read(dtdfile))
    when :nokogiri
      # For some reason there isn't a straightforward way to load a standalone
      # DTD in Nokogiri
      dtddoctext = '<!DOCTYPE dtd [' + File.read(dtdfile) + ']'
      dtddoc = Nokogiri::XML(dtddoctext)
      dtddoc.children.first
    when :rexml
      nil
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  # Returns true if validation is successful, or if validation is not
  # supported by the XML library in use.  Raises an exception if validation
  # fails.
  def self.xmlvalidate(xmldoc, dtd)
    case Etch.xmllib
    when :libxml
      result = xmldoc.validate(dtd)
      # LibXML::XML::Document#validate is documented to return false if
      # validation fails.  However, as currently implemented it raises an
      # exception instead.  Just in case that behavior ever changes raise an
      # exception if a false value is returned.
      if result
        true
      else
        raise "Validation failed"
      end
    when :nokogiri
      errors = dtd.validate(xmldoc)
      if errors.empty?
        true
      else
        raise errors.join('|')
      end
    when :rexml
      true
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlnewelem(name, doc)
    case Etch.xmllib
    when :libxml
      LibXML::XML::Node.new(name)
    when :nokogiri
      Nokogiri::XML::Element.new(name, doc)
    when :rexml
      REXML::Element.new(name)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmleach(xmldoc, xpath, &block)
    case Etch.xmllib
    when :libxml
      xmldoc.find(xpath).each(&block)
    when :nokogiri
      xmldoc.xpath(xpath).each(&block)
    when :rexml
      xmldoc.elements.each(xpath, &block)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmleachall(xmldoc, &block)
    case Etch.xmllib
    when :libxml
      if xmldoc.kind_of?(LibXML::XML::Document)
        xmldoc.root.each_element(&block)
      else
        xmldoc.each_element(&block)
      end
    when :nokogiri
      if xmldoc.kind_of?(Nokogiri::XML::Document)
        xmldoc.root.element_children.each(&block)
      else
        xmldoc.element_children.each(&block)
      end
    when :rexml
      if xmldoc.node_type == :document
        xmldoc.root.elements.each(&block)
      else
        xmldoc.elements.each(&block)
      end
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmleachattrall(elem, &block)
    case Etch.xmllib
    when :libxml
      elem.attributes.each(&block)
    when :nokogiri
      elem.attribute_nodes.each(&block)
    when :rexml
      elem.attributes.each_attribute(&block)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlarray(xmldoc, xpath)
    case Etch.xmllib
    when :libxml
      elements = xmldoc.find(xpath)
      if elements
        elements.to_a
      else
        []
      end
    when :nokogiri
      xmldoc.xpath(xpath).to_a
    when :rexml
      xmldoc.elements.to_a(xpath)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlfindfirst(xmldoc, xpath)
    case Etch.xmllib
    when :libxml
      xmldoc.find_first(xpath)
    when :nokogiri
      xmldoc.at_xpath(xpath)
    when :rexml
      xmldoc.elements[xpath]
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmltext(elem)
    case Etch.xmllib
    when :libxml
      elem.content
    when :nokogiri
      elem.content
    when :rexml
      text = elem.text
      # REXML returns nil rather than '' if there is no text
      if text
        text
      else
        ''
      end
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlsettext(elem, text)
    case Etch.xmllib
    when :libxml
      elem.content = text
    when :nokogiri
      elem.content = text
    when :rexml
      elem.text = text
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmladd(xmldoc, xpath, name, contents=nil)
    case Etch.xmllib
    when :libxml
      elem = LibXML::XML::Node.new(name)
      if contents
        elem.content = contents
      end
      xmldoc.find_first(xpath) << elem
    when :nokogiri
      elem = Nokogiri::XML::Node.new(name, xmldoc)
      if contents
        elem.content = contents
      end
      xmldoc.at_xpath(xpath) << elem
    when :rexml
      elem = REXML::Element.new(name)
      if contents
        elem.text = contents
      end
      xmldoc.elements[xpath].add_element(elem)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlcopyelem(elem, destelem)
    case Etch.xmllib
    when :libxml
      destelem << elem.copy(true)
    when :nokogiri
      destelem << elem.dup
    when :rexml
      destelem.add_element(elem.clone)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlremove(xmldoc, element)
    case Etch.xmllib
    when :libxml
      element.remove!
    when :nokogiri
      element.remove
    when :rexml
      if xmldoc.node_type == :document
        xmldoc.root.elements.delete(element)
      else
        xmldoc.elements.delete(element)
      end
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlremovepath(xmldoc, xpath)
    case Etch.xmllib
    when :libxml
      xmldoc.find(xpath).each { |elem| elem.remove! }
    when :nokogiri
      xmldoc.xpath(xpath).each { |elem| elem.remove }
    when :rexml
      elem = nil
      # delete_element only removes the first match, so call it in a loop
      # until it returns nil to indicate no matching element remain
      begin
        elem = xmldoc.delete_element(xpath)
      end while elem != nil
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlattradd(elem, attrname, attrvalue)
    case Etch.xmllib
    when :libxml
      elem.attributes[attrname] = attrvalue
    when :nokogiri
      elem[attrname] = attrvalue
    when :rexml
      elem.add_attribute(attrname, attrvalue)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  def self.xmlattrremove(elem, attribute)
    case Etch.xmllib
    when :libxml
      attribute.remove!
    when :nokogiri
      attribute.remove
    when :rexml
      elem.attributes.delete(attribute)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  
  # Used where we wish to capture an exception and modify the message.  This
  # method returns a new exception with desired message but with the backtrace
  # from the original exception so that the backtrace info is not lost.  This
  # is necessary because Exception lacks a set_message method.
  def self.wrap_exception(e, message)
    eprime = e.exception(message)
    eprime.set_backtrace(e.backtrace)
    eprime
  end
end

class EtchExternalSource
  def initialize(file, original_file, facts, groups, local_requests, sourcebase, commandsbase, sitelibbase, dlogger)
    # The external source is going to be processed within the same Ruby
    # instance as etch.  We want to make it clear what variables we are
    # intentionally exposing to external sources, essentially this
    # defines the "API" for those external sources.
    @file = file
    @original_file = original_file
    @facts = facts
    @groups = groups
    @local_requests = local_requests
    @sourcebase = sourcebase
    @commandsbase = commandsbase
    @sitelibbase = sitelibbase
    @dlogger = dlogger
  end

  # This method processes an ERB template (as specified via a <template>
  # entry in a config.xml file) and returns the results.
  def process_template(template)
    @dlogger.debug "Processing template #{template} for file #{@file}"
    # The '-' arg allows folks to use <% -%> or <%- -%> to instruct ERB to
    # not insert a newline for that line, which helps avoid a bunch of blank
    # lines in the processed file where there was code in the template.
    erb = ERB.new(IO.read(template), nil, '-')
    # The binding arg ties the template's namespace to this point in the
    # code, thus ensuring that all of the variables above (@file, etc.)
    # are visible to the template code.
    begin
      erb.result(binding)
    rescue Exception => e
      # Help the user figure out where the exception occurred, otherwise they
      # just get told it happened here, which isn't very helpful.
      raise Etch.wrap_exception(e, "Exception while processing template #{template} for file #{@file}:\n" + e.message)
    end
  end

  # This method runs a etch script (as specified via a <script> entry
  # in a config.xml file) and returns any output that the script puts in
  # the @contents variable.
  def run_script(script)
    @dlogger.debug "Processing script #{script} for file #{@file}"
    @contents = ''
    begin
      run_script_stage2(script)
    rescue Exception => e
      if e.kind_of?(SystemExit)
        # The user might call exit within a script.  We want the scripts
        # to act as much like a real script as possible, so ignore those.
      else
        # Help the user figure out where the exception occurred, otherwise they
        # just get told it happened here in eval, which isn't very helpful.
        raise Etch.wrap_exception(e, "Exception while processing script #{script} for file #{@file}:\n" + e.message)
      end
    end
    @contents
  end
  # The user might call return within a script.  We want the scripts to act as
  # much like a real script as possible.  Wrapping the eval in an extra method
  # allows us to handle a return within the script seamlessly.  If the user
  # calls return it triggers a return from this method.  Otherwise this method
  # returns naturally.  Either works for us.
  def run_script_stage2(script)
    eval(IO.read(script))
  end
end

