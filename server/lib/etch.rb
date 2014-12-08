# Exclude standard libraries and gems from the warnings induced by
# running ruby with the -w flag.  Several of these have warnings under
# ruby 1.9 and there's nothing we can do to fix that.
require 'silently'
Silently.silently do
  require 'find'        # Find.find
  require 'pathname'    # absolute?
  require 'digest/sha1' # hexdigest
  require 'base64'      # decode64, encode64
  require 'fileutils'   # mkdir_p
  require 'erb'
  require 'logger'
  require 'yaml'
  require 'set'
end
require 'versiontype' # Version

class Etch
  def self.xmllib
    @@xmllib
  end
  def self.xmllib=(lib)
    @@xmllib=lib
  end
end

# By default we try to use nokogiri, falling back to rexml if it is not
# available.  The xmllib environment variable can be used to force a specific
# library, mostly for testing purposes.
Silently.silently do
  begin
    if !ENV['xmllib'] || ENV['xmllib'] == 'nokogiri'
      require 'rubygems'  # nokogiri is a gem
      require 'nokogiri'
      Etch.xmllib = :nokogiri
    elsif ENV['xmllib'] == 'libxml'
      require 'rubygems'  # libxml is a gem
      require 'libxml'
      Etch.xmllib = :libxml
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
end

class Etch
  # FIXME: I'm not really proud of this, it seems like there ought to be a way
  # to just use one logger.  The problem is that on the server we'd like to
  # use Rails.logger for general logging (which is logging to
  # log/production.log), but be able to turn on debug-level logging for
  # individual connections (via the debug parameter sent in the HTTP
  # requests).  If we twiddle the log level of Rails.logger then all
  # connections coming in at the same time as the debug connection will also
  # get logged as debug, making the logs confusing.  And if the debug
  # connection aborts for some reason we also risk leaving
  # Rails.logger set to debug, flooding the logs.  So it seems like we
  # need a seperate logger for debugging.  But that just seems wrong somehow. 
  # We don't want to just dup Rails.logger for each connection, even
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
    
    #
    # These will be loaded on demand so that all-YAML configurations don't require them
    #
    
    @config_dtd = nil
    @commands_dtd = nil
    
    #
    # Load the defaults file which sets defaults for parameters that the
    # users don't specify in their config files.
    #
    
    @defaults = load_defaults
    
    #
    # Load the nodes file
    #

    groups = Set.new
    @nodes, nodesfile = load_nodes
    # Extract the groups for this node
    if @nodes[@fqdn]
      @nodes[@fqdn].each{|group| groups << group}
    else
      @logger.warn "No entry found for node #{@fqdn} in #{nodesfile}"
      # Some folks might want to terminate here
      #raise "No entry found for node #{@fqdn} in #{nodesfile}"
    end
    @dlogger.debug "Native groups for node #{@fqdn}: #{groups.sort.join(',')}"

    #
    # Load the node groups file
    #

    @group_hierarchy = load_nodegroups

    # Fill out the list of groups for this node with any parent groups
    parents = Set.new
    groups.each do |group|
      parents.merge get_parent_nodegroups(group)
    end
    parents.each{|parent| groups << parent}
    @dlogger.debug "Added groups for node #{@fqdn} due to node group hierarchy: #{parents.sort.join(',')}"

    #
    # Run the external node grouper
    #

    externals = Set.new
    IO.popen(File.join(@configdir, 'nodegrouper') + ' ' + @fqdn) do |pipe|
      pipe.each{|group| externals << group.chomp}
    end
    if !$?.success?
      raise "External node grouper #{File.join(@configdir, 'nodegrouper')} exited with error #{$?.exitstatus}"
    end
    groups.merge externals
    @dlogger.debug "Added groups for node #{@fqdn} due to external node grouper: #{externals.sort.join(',')}"

    @groups = groups.sort
    @dlogger.debug "Total groups for node #{@fqdn}: #{@groups.join(',')}"

    #
    # Build up a list of files to generate, either from the request or from
    # the source repository if the request is for all files
    #

    filelist = []
    if request.empty?
      @dlogger.debug "Building complete file list for request from #{@fqdn}"
      if File.exist?(@sourcebase)
        Find.find(@sourcebase) do |path|
          if File.directory?(path) &&
             (File.exist?(File.join(path, 'config.xml')) ||
              File.exist?(File.join(path, 'config.yml')))
            # Strip @sourcebase from start of path
            filelist << path.sub(Regexp.new('\A' + Regexp.escape(@sourcebase)), '')
          end
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
    @need_orig = []
    @commands = {}
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
      if File.exist?(@commandsbase)
        Find.find(@commandsbase) do |path|
          if File.directory?(path) &&
             (File.exist?(File.join(path, 'commands.yml')) ||
              File.exist?(File.join(path, 'commands.xml')))
            commandnames << File.basename(path)
          end
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
     :commands => @commands,
     :retrycommands => @retrycommands}
  end

  #
  # Private subroutines
  #
  private

  def load_defaults
    yamldefaults = "#{@configdir}/defaults.yml"
    xmldefaults = "#{@configdir}/defaults.xml"
    if File.exist?(yamldefaults)
      @dlogger.debug "Loading defaults from #{yamldefaults}"
      defaults = symbolize_etch_keys(YAML.load(File.read(yamldefaults)))
    elsif File.exist?(xmldefaults)
      @dlogger.debug "Loading defaults from #{xmldefaults}"
      defaults = {}
      defaults_xml = Etch.xmlload(xmldefaults)
      Etch.xmleach(defaults_xml, '/config/*') do |node|
        section = node.name.to_sym
        defaults[section] ||= {}
        Etch.xmleachall(node) do |entry|
          value = Etch.xmltext(entry)
          # Convert things that look like numbers to match how YAML is parsed
          if value.to_i.to_s == value
            value = value.to_i
          end
          defaults[section][entry.name.to_sym] = value
        end
      end
    else
      raise "Neither defaults.yml nor defaults.xml exists"
    end
    # Ensure the top level sections exist
    [:file, :link, :directory].each{|top| defaults[top] ||= {}}
    defaults
  end
  def symbolize_etch_key(key)
    key =~ /\Awhere (.*)/ ? key : key.to_sym
  end
  def symbolize_etch_keys(hash)
    case hash
    when Hash
      Hash[hash.collect{|k,v| [symbolize_etch_key(k), symbolize_etch_keys(v)]}]
    when Array
      hash.collect{|e| symbolize_etch_keys(e)}
    else
      hash
    end
  end
  def load_nodes
    yamlnodes = "#{@configdir}/nodes.yml"
    xmlnodes = "#{@configdir}/nodes.xml"
    if File.exist?(yamlnodes)
      @dlogger.debug "Loading native groups from #{yamlnodes}"
      nodesfile = 'nodes.yml'
      nodes = YAML.load(File.read(yamlnodes))
      nodes ||= {}
    elsif File.exist?(xmlnodes)
      @dlogger.debug "Loading native groups from #{xmlnodes}"
      nodesfile = 'nodes.xml'
      nodes_xml = Etch.xmlload(xmlnodes)
      nodes = {}
      Etch.xmleach(nodes_xml, '/nodes/node') do |node|
        name = Etch.xmlattrvalue(node, 'name')
        nodes[name] ||= []
        Etch.xmleach(node, 'group') do |group|
          nodes[name] << Etch.xmltext(group)
        end
      end
    end
    nodes ||= {}
    nodesfile ||= '<none>'
    [nodes, nodesfile]
  end
  def load_nodegroups
    yamlnodegroups = "#{@configdir}/nodegroups.yml"
    xmlnodegroups = "#{@configdir}/nodegroups.xml"
    if File.exist?(yamlnodegroups)
      @dlogger.debug "Loading node group hierarchy from #{yamlnodegroups}"
      group_hierarchy = YAML.load(File.read(yamlnodegroups))
    elsif File.exist?(xmlnodegroups)
      @dlogger.debug "Loading node group hierarchy from #{xmlnodegroups}"
      group_hierarchy = {}
      nodegroups_xml = Etch.xmlload(xmlnodegroups)
      Etch.xmleach(nodegroups_xml, '/nodegroups/nodegroup') do |parent|
        parentname = Etch.xmlattrvalue(parent, 'name')
        group_hierarchy[parentname] ||= []
        Etch.xmleach(parent, 'child') do |child|
          group_hierarchy[parentname] << Etch.xmltext(child)
        end
      end
    end
    group_hierarchy || {}
  end

  # Recursive method to get all of the parents of a node group
  def get_parent_nodegroups(group)
    parents = Set.new
    @group_hierarchy.each do |parent, children|
      if children.include?(group)
        parents << parent
        parents.merge get_parent_nodegroups(parent)
      end
    end
    parents
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
    
    config = load_config(file)
    
    generation_status = :unknown
    # As we go through the process of generating the file we'll end up with
    # four possible outcomes:
    # fatal error: raise an exception
    # failure: we're missing needed data for this file or a dependency,
    #          generally the original file
    # success: we successfully processed a valid configuration
    # unknown: no valid configuration nor errors encountered, probably because
    #          filtering removed everything from the config file.  This
    #          should be considered a successful outcome, it indicates the
    #          caller/client provided us with all required data and our result
    #          is that no action needs to be taken.
    # We keep track of which of the failure, success or unknown states we end
    # up in via the generation_status variable.  We initialize it to :unknown.
    # If we encounter either failure or success we set it to false or :success.
    catch :generate_done do
      # Generate any other files that this file depends on
      proceed = true
      config[:depend] && config[:depend].each do |depend|
        @dlogger.debug "Generating dependency #{depend}"
        r = generate_file(depend, request)
        proceed = proceed && r
      end
      # Also generate any commands that this file depends on
      config[:dependcommand] && config[:dependcommand].each do |dependcommand|
        @dlogger.debug "Generating command dependency #{dependcommand}"
        r = generate_commands(dependcommand, request)
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
        config[:depend] && config[:depend].each {|depend| @need_orig << depend}
        
        # Tell the client to request this file again
        @need_orig << file
        
        # Strip this file's config down to the bare necessities
        filter_config_completely!(config, [:depend, :setup])
        
        # And hit the eject button
        generation_status = false
        throw :generate_done
      end
      
      # Change into the corresponding directory so that the user can
      # refer to source files and scripts by their relative pathnames.
      Dir.chdir "#{@sourcebase}/#{file}"

      # See what type of action the user has requested

      # Check to see if the user has requested that we revert back to the
      # original file.
      if config[:revert]
        # Pass the revert action back to the client
        filter_config!(config, [:revert])
        generation_status = :success
        throw :generate_done
      end
  
      # Perform any server setup commands
      if config[:server_setup]
        @dlogger.debug "Processing server setup commands"
        config[:server_setup].each do |cmd|
          @dlogger.debug "  Executing #{cmd}"
          # Explicitly invoke using /bin/sh so that syntax like
          # "FOO=bar myprogram" works.
          success = system('/bin/sh', '-c', cmd)
          if !success
            raise "Server setup command #{cmd} for file #{file} exited with non-zero value"
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

      if config[:file]
        #
        # Assemble the contents for the file
        #
        newcontents = ''
        if config[:file][:plain] && !config[:file][:plain].empty?
          if config[:file][:plain].kind_of?(Array)
            if check_for_inconsistency(config[:file][:plain])
              raise "Inconsistent 'plain' entries for #{file}"
            end
            plain = config[:file][:plain].first
          else
            plain = config[:file][:plain]
          end
          # Just slurp the file in
          newcontents = IO.read(plain)
        elsif config[:file][:template] && !config[:file][:template].empty?
          if config[:file][:template].kind_of?(Array)
            if check_for_inconsistency(config[:file][:template])
              raise "Inconsistent 'template' entries for #{file}"
            end
            template = config[:file][:template].first
          else
            template = config[:file][:template]
          end
          # Run the template through ERB to generate the file contents
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          newcontents = external.process_template(template)
        elsif config[:file][:script] && !config[:file][:script].empty?
          if config[:file][:script].kind_of?(Array)
            if check_for_inconsistency(config[:file][:script])
              raise "Inconsistent 'script' entries for #{file}"
            end
            script = config[:file][:script].first
          else
            script = config[:file][:script]
          end
          # Run the script to generate the file contents
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          newcontents = external.run_script(script)
        elsif config[:file][:always_manage_metadata]
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
            ! config[:file][:allow_empty] &&
            ! config[:file][:always_manage_metadata]
          @dlogger.debug "New contents for file #{file} empty, doing nothing"
        else
          # Finish assembling the file contents as long as we're not
          # proceeding based only on always_manage_metadata.  If we are
          # proceeding based only on always_manage_metadata we want to make
          # sure that the only action we'll take is to manage metadata, not
          # muck with the file's contents.
          if !(newcontents == '' && config[:file][:always_manage_metadata])
            # Add the warning message (if defined)
            warning_file = nil
            if config[:file][:warning_file] && !config[:file][:warning_file].empty?
              warning_file = config[:file][:warning_file]
            # This allows the user to set warning_file to false or an empty string in their
            # config file to prevent the use of the default warning file
            elsif !config[:file].include?(:warning_file)
              warning_file = @defaults[:file][:warning_file]
            end
            if warning_file
              warnpath = Pathname.new(warning_file)
              if !File.exist?(warning_file) && !warnpath.absolute?
                warning_file = File.expand_path(warning_file, @configdir)
              end
            end
            if warning_file && File.exist?(warning_file)
              warning = ''

              # First the comment opener
              comment_open = config[:file][:comment_open] || @defaults[:file][:comment_open]
              if comment_open && !comment_open.empty?
                warning << comment_open << "\n"
              end

              # Then the message
              comment_line = config[:file][:comment_line] || @defaults[:file][:comment_line] || '# '

              File.open(warning_file) do |warnfile|
                while line = warnfile.gets
                  warning << comment_line << line
                end
              end

              # And last the comment closer
              comment_close = config[:file][:comment_close] || @defaults[:file][:comment_close]
              if comment_close && !comment_close.empty?
                warning << comment_close << "\n"
              end

              # By default we insert the warning at the top of the
              # generated file.  However, some files (particularly
              # scripts) have a special first line.  The user can flag
              # those files to have the warning inserted starting at the
              # second line.
              if !config[:file][:warning_on_second_line]
                # And then other files (notably Solaris crontabs) can't
                # have any blank lines.  Normally we insert a blank
                # line between the warning message and the generated
                # file to improve readability.  The user can flag us to
                # not insert that blank line.
                if !config[:file][:no_space_around_warning]
                  newcontents = warning << "\n" << newcontents
                else
                  newcontents = warning << newcontents
                end
              else
                parts = newcontents.split("\n", 2)
                if !config[:file][:no_space_around_warning]
                  newcontents = parts[0] << "\n\n" << warning << "\n" << parts[1]
                else
                  newcontents = parts[0] << warning << parts[1]
                end
              end
            end # if warning_file
    
            # Add the generated file contents to the XML
            config[:file][:contents] = Base64.encode64(newcontents)
          end

          # Remove the source configuration from the config, the
          # client won't need to see it
          config[:file].delete(:plain)
          config[:file].delete(:template)
          config[:file].delete(:script)

          # Remove all of the warning related elements from the config, the
          # client won't need to see them
          config[:file].delete(:warning_file)
          config[:file].delete(:warning_on_second_line)
          config[:file].delete(:no_space_around_warning)
          config[:file].delete(:comment_open)
          config[:file].delete(:comment_line)
          config[:file].delete(:comment_close)
        
          # If the config doesn't contain ownership and permissions entries
          # then add appropriate ones based on the defaults
          if !config[:file][:owner]
            if @defaults[:file][:owner]
              config[:file][:owner] = @defaults[:file][:owner]
            else
              raise "defaults needs file->owner"
            end
          end
          if !config[:file][:group]
            if @defaults[:file][:group]
              config[:file][:group] = @defaults[:file][:group]
            else
              raise "defaults needs file->group"
            end
          end
          if !config[:file][:perms]
            if @defaults[:file][:perms]
              config[:file][:perms] = @defaults[:file][:perms]
            else
              raise "defaults needs file->perms"
            end
          end
      
          # Send the file contents and metadata to the client
          filter_config!(config, [:file])
      
          generation_status = :success
          throw :generate_done
        end
      end

      #
      # Symbolic link
      #
  
      if config[:link]
        dest = nil
        if config[:link][:dest] && !config[:link][:dest].empty?
          if config[:link][:dest].kind_of?(Array)
            if check_for_inconsistency(config[:link][:dest])
              raise "Inconsistent 'dest' entries for #{file}"
            end
            dest = config[:link][:dest].first
          else
            dest = config[:link][:dest]
          end
        elsif config[:link][:script] && !config[:link][:script].empty?
          # The user can specify a script to perform more complex
          # testing to decide whether to create the link or not and
          # what its destination should be.
          if config[:link][:script].kind_of?(Array)
            if check_for_inconsistency(config[:link][:script])
              raise "Inconsistent 'script' entries for #{file}"
            end
            script = config[:link][:script].first
          else
            script = config[:link][:script]
          end
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          dest = external.run_script(script)
          # Remove the script entry from the config, the client won't need
          # to see it
          config[:link].delete(:script)
        else
          # If the filtering has removed the destination for the link,
          # that means it doesn't apply to this node.
          @dlogger.debug "No configuration for link #{file} destination, doing nothing"
        end

        if !dest || dest.empty?
          @dlogger.debug "Destination for link #{file} empty, doing nothing"
        else
          config[:link][:dest] = dest

          # If the config doesn't contain ownership and permissions entries
          # then add appropriate ones based on the defaults
          if !config[:link][:owner]
            if @defaults[:link][:owner]
              config[:link][:owner] = @defaults[:link][:owner]
            else
              raise "defaults needs link->owner"
            end
          end
          if !config[:link][:group]
            if @defaults[:link][:group]
              config[:link][:group] = @defaults[:link][:group]
            else
              raise "defaults needs link->group"
            end
          end
          if !config[:link][:perms]
            if @defaults[:link][:perms]
              config[:link][:perms] = @defaults[:link][:perms]
            else
              raise "defaults needs link->perms"
            end
          end
      
          # Send the file contents and metadata to the client
          filter_config!(config, [:link])

          generation_status = :success
          throw :generate_done
        end
      end

      #
      # Directory
      #
  
      if config[:directory]
        create = false
        if config[:directory][:create] &&
           (!config[:directory][:create].kind_of?(Array) || !config[:directory][:create].empty?)
          if config[:directory][:create].kind_of?(Array)
            if check_for_inconsistency(config[:directory][:create])
              raise "Inconsistent 'create' entries for #{file}"
            end
            create = config[:directory][:create].first
          else
            create = config[:directory][:create]
          end
        elsif config[:directory][:script] && !config[:directory][:script].empty?
          # The user can specify a script to perform more complex testing
          # to decide whether to create the directory or not.
          if config[:directory][:script].kind_of?(Array)
            if check_for_inconsistency(config[:directory][:script])
              raise "Inconsistent 'script' entries for #{file}"
            end
            script = config[:directory][:script].first
          else
            script = config[:directory][:script]
          end
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          create = external.run_script(script)
          create = false if create.empty?
          # Remove the script entry from the config, the client won't need
          # to see it
          config[:directory].delete(:script)
        else
          # If the filtering has removed the directive to create this
          # directory, that means it doesn't apply to this node.
          @dlogger.debug "No configuration to create directory #{file}, doing nothing"
        end
    
        if !create
          @dlogger.debug "Directive to create directory #{file} false, doing nothing"
        else
          config[:directory][:create] = create

          # If the config doesn't contain ownership and permissions entries
          # then add appropriate ones based on the defaults
          if !config[:directory][:owner]
            if @defaults[:directory][:owner]
              config[:directory][:owner] = @defaults[:directory][:owner]
            else
              raise "defaults.xml needs directory->owner"
            end
          end
          if !config[:directory][:group]
            if @defaults[:directory][:group]
              config[:directory][:group] = @defaults[:directory][:group]
            else
              raise "defaults.xml needs directory->group"
            end
          end
          if !config[:directory][:perms]
            if @defaults[:directory][:perms]
              config[:directory][:perms] = @defaults[:directory][:perms]
            else
              raise "defaults.xml needs directory->perms"
            end
          end
      
          # Send the file contents and metadata to the client
          filter_config!(config, [:directory])
      
          generation_status = :success
          throw :generate_done
        end
      end

      #
      # Delete whatever is there
      #

      if config[:delete]
        proceed = false
        if config[:delete][:proceed] &&
           (!config[:delete][:proceed].kind_of?(Array) || !config[:delete][:proceed].empty?)
          if config[:delete][:proceed].kind_of?(Array)
            if check_for_inconsistency(config[:delete][:proceed])
              raise "Inconsistent 'proceed' entries for #{file}"
            end
            proceed = config[:delete][:proceed].first
          else
            proceed = config[:delete][:proceed]
          end
        elsif config[:delete][:script] && !config[:delete][:script].empty?
          # The user can specify a script to perform more complex testing
          # to decide whether to delete the file or not.
          if config[:delete][:script].kind_of?(Array)
            if check_for_inconsistency(config[:delete][:script])
              raise "Inconsistent 'script' entries for #{file}"
            end
            script = config[:delete][:script].first
          else
            script = config[:delete][:script]
          end
          external = EtchExternalSource.new(file, original_file, @facts, @groups, local_requests, @sourcebase, @commandsbase, @sitelibbase, @dlogger)
          proceed = external.run_script(script)
          proceed = false if proceed.empty?
          # Remove the script entry from the config, the client won't need
          # to see it
          config[:delete].delete(:script)
        else
          # If the filtering has removed the directive to remove this
          # file, that means it doesn't apply to this node.
          @dlogger.debug "No configuration to delete #{file}, doing nothing"
        end
    
        if !proceed
          @dlogger.debug "Directive to delete #{file} false, doing nothing"
        else
          config[:delete][:proceed] = true

          # Send the file contents and metadata to the client
          filter_config!(config, [:delete])
      
          generation_status = :success
          throw :generate_done
        end
      end
    end
    
    # Earlier we chdir'd into the file's directory in the repository.  It
    # seems best not to leave this process with that as the cwd.
    Dir.chdir('/')
    
    # In addition to successful configs return configs for files that need
    # orig data (generation_status==false) because any setup commands might be
    # needed to create the original file.
    if generation_status != :unknown && !config.empty?
      @configs[file] = config
    end
  
    @already_generated[file] = true
    @filestack.delete(file)
    @generation_status[file] = generation_status
    
    generation_status
  end
  
  def load_config(file)
    yamlconfig = "#{@sourcebase}/#{file}/config.yml"
    xmlconfig = "#{@sourcebase}/#{file}/config.xml"
    if File.exist?(yamlconfig)
      config = symbolize_etch_keys(YAML.load(File.read(yamlconfig)))
      config ||= {}
      begin
        yamlfilter!(config)
      rescue Exception => e
        raise Etch.wrap_exception(e, "Error filtering config.yml for #{file}:\n" + e.message)
      end
    elsif File.exist?(xmlconfig)
      # Load the config.xml file
      config_xml = nil
      begin
        config_xml = Etch.xmlload(xmlconfig)
      rescue Exception => e
        raise Etch.wrap_exception(e, "Error loading config.xml for #{file}:\n" + e.message)
      end
      # Filter the config.xml file by looking for attributes
      begin
        xmlfilter!(Etch.xmlroot(config_xml))
      rescue Exception => e
        raise Etch.wrap_exception(e, "Error filtering config.xml for #{file}:\n" + e.message)
      end
      # Validate the filtered file against config.dtd
      @config_dtd ||= Etch.xmlloaddtd(@config_dtd_file)
      begin
        Etch.xmlvalidate(config_xml, @config_dtd)
      rescue Exception => e
        raise Etch.wrap_exception(e, "Filtered config.xml for #{file} fails validation:\n" + e.message)
      end
      config = Etch.config_xml_to_hash(config_xml)
    else
      raise "config.yml or config.xml for #{file} does not exist"
    end
    config
  end

  # Returns the value of the generation_status variable, see comments in
  # method for possible values.
  def generate_commands(command, request)
    # Skip commands we've already generated in response to <depend>
    # statements.
    if @already_generated[command]
      @dlogger.debug "Skipping already generated command #{command}"
      # Return the status of that previous generation
      return @generation_status[command]
    end
    
    # Check for circular dependencies, otherwise we're vulnerable
    # to going into an infinite loop
    if @filestack[command]
      raise "Circular dependency detected for command #{command}"
    end
    @filestack[command] = true
    
    cmd = load_command(command)
    
    generation_status = :unknown
    # As we go through the process of generating the command we'll end up with
    # four possible outcomes:
    # fatal error: raise an exception
    # failure: we're missing needed data for this command or a dependency,
    #          generally the original file for a file this command depends on
    # success: we successfully processed a valid configuration
    # unknown: no valid configuration nor errors encountered, probably because
    #          filtering removed everything from the commands file.  This
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
      cmd[:depend] && cmd[:depend].each do |depend|
        @dlogger.debug "Generating command dependency #{depend}"
        proceed &= generate_commands(depend, request)
      end
      # Also generate any files that this command depends on
      cmd[:dependfile] && cmd[:dependfile].each do |dependfile|
        @dlogger.debug "Generating file dependency #{dependfile}"
        dependfiles << dependfile
        proceed &= generate_file(dependfile, request)
      end
      if !proceed
        @dlogger.debug "One or more dependencies of #{command} need data from client"
        # If any file dependency failed to generate (due to a need for orig
        # contents from the client) then we need to tell the client to request
        # all of the files in the dependency tree again.  See the big comment
        # in generate_file for further explanation.
        dependfiles.each { |dependfile| @need_orig << dependfile }
        # Try again next time
        @retrycommands[command] = true
        generation_status = false
        throw :generate_done
      end
      
      if cmd[:steps]
        remove = []
        cmd[:steps].each do |outerstep|
          if step = outerstep[:step]
            if step[:guard] && !step[:guard].kind_of?(Array)
              step[:guard] = [step[:guard]]
            end
            if step[:command] && !step[:command].kind_of?(Array)
              step[:command] = [step[:command]]
            end
            # If filtering has removed both the guard and command elements
            # then we can remove this step.
            if (!step[:guard] || step[:guard].empty?) &&
               (!step[:command] || step[:command].empty?)
              remove << outerstep
            # If filtering has removed the guard but not the command or vice
            # versa that's an error.
            elsif !step[:guard] || step[:guard].empty?
              raise "Filtering removed guard, but left command: #{step[:command].join(';')}"
            elsif !step[:command] || step[:command].empty?
              raise "Filtering removed command, but left guard: #{step[:guard].join(';')}"
            else
              generation_status = :success
            end
          end
        end
        remove.each{|outerstep| cmd[:steps].delete(outerstep)}
      end
    end
    
    # If filtering didn't remove all the content then add this to the list of
    # commands to be returned to the client.
    if generation_status && generation_status != :unknown && !cmd.empty?
      @commands[command] = cmd
    end
    
    @already_generated[command] = true
    @filestack.delete(command)
    @generation_status[command] = generation_status
    
    generation_status
  end
  
  def load_command(command)
    yamlcommand = "#{@commandsbase}/#{command}/commands.yml"
    xmlcommand = "#{@commandsbase}/#{command}/commands.xml"
    if File.exist?(yamlcommand)
      cmd = symbolize_etch_keys(YAML.load(File.read(yamlcommand)))
      cmd ||= {}
      begin
        yamlfilter!(cmd)
      rescue Exception => e
        raise Etch.wrap_exception(e, "Error filtering commands.yml for #{command}:\n" + e.message)
      end
    elsif File.exist?(xmlcommand)
      # Load the commands.xml file
      begin
        command_xml = Etch.xmlload(xmlcommand)
      rescue Exception => e
        raise Etch.wrap_exception(e, "Error loading commands.xml for #{command}:\n" + e.message)
      end
      # Filter the commands.xml file by looking for attributes
      begin
        xmlfilter!(Etch.xmlroot(command_xml))
      rescue Exception => e
        raise Etch.wrap_exception(e, "Error filtering commands.xml for #{command}:\n" + e.message)
      end
      # Validate the filtered file against commands.dtd
      @commands_dtd ||= Etch.xmlloaddtd(@commands_dtd_file)
      begin
        Etch.xmlvalidate(command_xml, @commands_dtd)
      rescue Exception => e
        raise Etch.wrap_exception(e, "Filtered commands.xml for #{command} fails validation:\n" + e.message)
      end
      # Convert the filtered XML to a hash
      cmd = Etch.command_xml_to_hash(command_xml)
    else
      raise "commands.yml or commands.xml for #{command} does not exist"
    end
    cmd
  end

  ALWAYS_KEEP = [:depend, :setup, :pre, :test_before_post, :post, :post_once, :post_once_per_run, :test]
  def filter_config_completely!(config, keepers=[])
    config.reject!{|k,v| !keepers.include?(k)}
  end
  def filter_config!(config, keepers=[])
    filter_config_completely!(config, keepers.concat(ALWAYS_KEEP))
  end

  def yamlfilter!(yaml)
    result = false
    case yaml
    when Hash
      remove = []
      yaml.each do |k,v|
        if v.kind_of?(Hash) &&
           v.length == 1 &&
           v.keys.first =~ /\Awhere (.*)/
          if eval_yaml_condition($1)
            yaml[k] = v.values.first
          else
            remove << k
          end
        end
        yamlfilter!(v)
      end
      remove.each{|k| yaml.delete(k)}
    when Array
      keep = []
      yaml.each do |e|
        if e.kind_of?(Hash) &&
           e.length == 1 &&
           e.keys.first =~ /\Awhere (.*)/
          if eval_yaml_condition($1)
            keep << e.values.first
          end
        else
          keep << e
        end
        yamlfilter!(e)
      end
      yaml.replace(keep)
    end
  end
  # Examples:
  # operatingsystem==Solaris
  # operatingsystem=~RedHat|CentOS and group==bar
  # operatingsystem=~RedHat|CentOS or kernel == SunOS and group==bar
  def eval_yaml_condition(condition)
    exprs = condition.split(/\s+(and|or)\s+/)
    prevcond = nil
    result = nil
    exprs.each do |expr|
      case expr
      when 'and'
        prevcond = :and
      when 'or'
        prevcond = :or
      else
        value = nil
        case
        when expr =~ /(.+?)\s*=~\s*(.+)/
          comps = comparables($1)
          regexp = Regexp.new($2)
          value = comps.any?{|c| c =~ regexp}
        when expr =~ /(.+?)\s*!~\s*(.+)/
          comps = comparables($1)
          regexp = Regexp.new($2)
          value = comps.any?{|c| c !~ regexp}
        when expr =~ /(.+?)\s*(<|<=|>=|>)\s*(.+)/
          comps = comparables($1)
          operator = $2.to_sym
          valueversion = Version.new($3)
          value = comps.any?{|c| Version.new(c).send(operator, valueversion)}
        when expr =~ /(.+?)\s*==\s*(.+)/
          comps = comparables($1)
          value = comps.include?($2)
        when expr =~ /(.+?)\s*!=\s*(.+)/
          comps = comparables($1)
          value = !comps.include?($2)
        when expr =~ /(.+?)\s+in\s+(.+)/
          comps = comparables($1)
          list = $2.split(/\s*,\s*/)
          value = list.any?{|item| comps.include?(item)}
        when expr =~ /(.+?)\s+!in\s+(.+)/
          comps = comparables($1)
          list = $2.split(/\s*,\s*/)
          value = list.none?{|item| comps.include?(item)}
        else
          raise "Unable to parse '#{condition}'"
        end
        case prevcond
        when :and
          result = result && value
          # False ands short circuit
          if !result
            return result
          end
        when :or
          result = result || value
        else
          result = value
        end
      end
    end
    result
  end
  def xmlfilter!(element)
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
        xmlfilter!(elem)
      end
    end
    elem_remove.each { |elem| Etch.xmlremove(element, elem) }
  end

  def comparables(name)
    if name == 'group'
      @groups
    elsif @facts[name]
      [@facts[name]]
    end
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
    result = false
    negate = false
    
    # Negation
    # i.e. <plain os="!SunOS"></plain>
    if value =~ /^\!/
      negate = true
      value.sub!(/^\!/, '')  # Strip off the bang
    end
    
    comps = comparables(name)
    comps && comps.each do |comp|
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
  
  def self.config_xml_to_hash(config_xml)
    config = {}

    if Etch.xmlfindfirst(config_xml, '/config/revert')
      config[:revert] = true
    end

    Etch.xmleach(config_xml, '/config/depend') do |depend|
      config[:depend] ||= []
      config[:depend] << Etch.xmltext(depend)
    end
    Etch.xmleach(config_xml, '/config/dependcommand') do |dependcommand|
      config[:dependcommand] ||= []
      config[:dependcommand] << Etch.xmltext(dependcommand)
    end

    Etch.xmleach(config_xml, '/config/server_setup/exec') do |cmd|
      config[:server_setup] ||= []
      config[:server_setup] << Etch.xmltext(cmd)
    end
    Etch.xmleach(config_xml, '/config/setup/exec') do |cmd|
      config[:setup] ||= []
      config[:setup] << Etch.xmltext(cmd)
    end
    Etch.xmleach(config_xml, '/config/pre/exec') do |cmd|
      config[:pre] ||= []
      config[:pre] << Etch.xmltext(cmd)
    end

    if Etch.xmlfindfirst(config_xml, '/config/file')
      config[:file] = {}
    end
    [:owner, :group, :perms, :warning_file, :comment_open,
     :comment_line, :comment_close].each do |meta|
      if metaelem = Etch.xmlfindfirst(config_xml, "/config/file/#{meta}")
        config[:file][meta] = Etch.xmltext(metaelem)
      end
    end
    [:always_manage_metadata, :warning_on_second_line,
     :no_space_around_warning, :allow_empty,
     :overwrite_directory].each do |bool|
      if Etch.xmlfindfirst(config_xml, "/config/file/#{bool}")
        config[:file][bool] = true
      end
    end
    [:plain, :template, :script].each do |sourcetype|
      Etch.xmleach(config_xml, "/config/file/source/#{sourcetype}") do |sourceelem|
        config[:file][sourcetype] ||= []
        config[:file][sourcetype] << Etch.xmltext(sourceelem)
      end
    end

    if Etch.xmlfindfirst(config_xml, '/config/link')
      config[:link] = {}
    end
    [:owner, :group, :perms].each do |meta|
      if metaelem = Etch.xmlfindfirst(config_xml, "/config/link/#{meta}")
        config[:link][meta] = Etch.xmltext(metaelem)
      end
    end
    [:allow_nonexistent_dest, :overwrite_directory].each do |bool|
      if Etch.xmlfindfirst(config_xml, "/config/link/#{bool}")
        config[:link][bool] = true
      end
    end
    [:dest, :script].each do |sourcetype|
      Etch.xmleach(config_xml, "/config/link/#{sourcetype}") do |sourceelem|
        config[:link][sourcetype] ||= []
        config[:link][sourcetype] << Etch.xmltext(sourceelem)
      end
    end

    if Etch.xmlfindfirst(config_xml, '/config/directory')
      config[:directory] = {}
    end
    [:owner, :group, :perms].each do |meta|
      if metaelem = Etch.xmlfindfirst(config_xml, "/config/directory/#{meta}")
        config[:directory][meta] = Etch.xmltext(metaelem)
      end
    end
    [:create].each do |bool|
      if Etch.xmlfindfirst(config_xml, "/config/directory/#{bool}")
        config[:directory][bool] = true
      end
    end
    [:script].each do |sourcetype|
      Etch.xmleach(config_xml, "/config/directory/#{sourcetype}") do |sourceelem|
        config[:directory][sourcetype] ||= []
        config[:directory][sourcetype] << Etch.xmltext(sourceelem)
      end
    end

    if Etch.xmlfindfirst(config_xml, '/config/delete')
      config[:delete] = {}
    end
    [:overwrite_directory, :proceed].each do |bool|
      if Etch.xmlfindfirst(config_xml, "/config/delete/#{bool}")
        config[:delete][bool] = true
      end
    end
    [:script].each do |sourcetype|
      Etch.xmleach(config_xml, "/config/delete/#{sourcetype}") do |sourceelem|
        config[:delete][sourcetype] ||= []
        config[:delete][sourcetype] << Etch.xmltext(sourceelem)
      end
    end

    Etch.xmleach(config_xml, '/config/test_before_post/exec') do |cmd|
      config[:test_before_post] ||= []
      config[:test_before_post] << Etch.xmltext(cmd)
    end
    Etch.xmleach(config_xml, '/config/post/exec') do |cmd|
      config[:post] ||= []
      config[:post] << Etch.xmltext(cmd)
    end
    Etch.xmleach(config_xml, '/config/post/exec_once') do |cmd|
      config[:post_once] ||= []
      config[:post_once] << Etch.xmltext(cmd)
    end
    Etch.xmleach(config_xml, '/config/post/exec_once_per_run') do |cmd|
      config[:post_once_per_run] ||= []
      config[:post_once_per_run] << Etch.xmltext(cmd)
    end
    Etch.xmleach(config_xml, '/config/test/exec') do |cmd|
      config[:test] ||= []
      config[:test] << Etch.xmltext(cmd)
    end

    config
  end
  def self.config_hash_to_xml(config, file)
    doc = Etch.xmlnewdoc
    root = Etch.xmlnewelem('config', doc)
    Etch.xmlattradd(root, 'filename', file)
    Etch.xmlsetroot(doc, root)
    if config[:revert]
      root << Etch.xmlnewelem('revert', doc)
    end
    if config[:depend]
      config[:depend].each do |depend|
        depelem = Etch.xmlnewelem('depend', doc)
        Etch.xmlsettext(depelem, depend)
        root << depelem
      end
    end
    if config[:dependcommand]
      config[:dependcommand].each do |dependcommand|
        depelem = Etch.xmlnewelem('dependcommand', doc)
        Etch.xmlsettext(depelem, dependcommand)
        root << depelem
      end
    end
    if config[:setup]
      elem = Etch.xmlnewelem('setup', doc)
      config[:setup].each do |exec|
        execelem = Etch.xmlnewelem('exec', doc)
        Etch.xmlsettext(execelem, exec)
        elem << execelem
      end
      root << elem
    end
    if config[:pre]
      elem = Etch.xmlnewelem('pre', doc)
      config[:pre].each do |exec|
        execelem = Etch.xmlnewelem('exec', doc)
        Etch.xmlsettext(execelem, exec)
        elem << execelem
      end
      root << elem
    end
    if config[:file]
      fileelem = Etch.xmlnewelem('file', doc)
      root << fileelem
      [:owner, :group, :perms].each do |text|
        if config[:file][text]
          textelem = Etch.xmlnewelem(text.to_s, doc)
          Etch.xmlsettext(textelem, config[:file][text])
          fileelem << textelem
        end
      end
      [:overwrite_directory].each do |bool|
        if config[:file][bool]
          boolelem = Etch.xmlnewelem(bool.to_s, doc)
          fileelem << boolelem
        end
      end
      if config[:file][:contents]
        elem = Etch.xmlnewelem('contents', doc)
        Etch.xmlsettext(elem, config[:file][:contents])
        fileelem << elem
      end
    end
    if config[:link]
      linkelem = Etch.xmlnewelem('link', doc)
      root << linkelem
      [:owner, :group, :perms].each do |text|
        if config[:link][text]
          textelem = Etch.xmlnewelem(text.to_s, doc)
          Etch.xmlsettext(textelem, config[:link][text])
          linkelem << textelem
        end
      end
      [:allow_nonexistent_dest, :overwrite_directory].each do |bool|
        if config[:link][bool]
          boolelem = Etch.xmlnewelem(bool.to_s, doc)
          linkelem << boolelem
        end
      end
      if config[:link][:dest]
        elem = Etch.xmlnewelem('dest', doc)
        Etch.xmlsettext(elem, config[:link][:dest])
        linkelem << elem
      end
    end
    if config[:directory]
      direlem = Etch.xmlnewelem('directory', doc)
      root << direlem
      [:owner, :group, :perms].each do |text|
        if config[:directory][text]
          textelem = Etch.xmlnewelem(text.to_s, doc)
          Etch.xmlsettext(textelem, config[:directory][text])
          direlem << textelem
        end
      end
      [:create].each do |bool|
        if config[:directory][bool]
          boolelem = Etch.xmlnewelem(bool.to_s, doc)
          direlem << boolelem
        end
      end
    end
    if config[:delete]
      deleteelem = Etch.xmlnewelem('delete', doc)
      root << deleteelem
      [:overwrite_directory, :proceed].each do |bool|
        if config[:delete][bool]
          boolelem = Etch.xmlnewelem(bool.to_s, doc)
          deleteelem << boolelem
        end
      end
    end
    if config[:test_before_post]
      elem = Etch.xmlnewelem('test_before_post', doc)
      config[:test_before_post].each do |exec|
        execelem = Etch.xmlnewelem('exec', doc)
        Etch.xmlsettext(execelem, exec)
        elem << execelem
      end
      root << elem
    end
    postelem = nil
    {
      :post_once => :exec_once,
      :post_once_per_run => :exec_once_per_run,
      :post => :exec,
        }.each do |posttype, xmltype|
      if config[posttype]
        if !postelem
          postelem = Etch.xmlnewelem('post', doc)
          root << postelem
        end
        config[posttype].each do |postexec|
          execelem = Etch.xmlnewelem(xmltype.to_s, doc)
          Etch.xmlsettext(execelem, postexec)
          postelem << execelem
        end
      end
    end
    if config[:test]
      elem = Etch.xmlnewelem('test', doc)
      config[:test].each do |exec|
        execelem = Etch.xmlnewelem('exec', doc)
        Etch.xmlsettext(execelem, exec)
        elem << execelem
      end
      root << elem
    end
    doc
  end
  def self.command_xml_to_hash(command_xml)
    cmd = {}
    Etch.xmleach(command_xml, '/commands/depend') do |depend|
      cmd[:depend] ||= []
      cmd[:depend] << Etch.xmltext(depend)
    end
    Etch.xmleach(command_xml, '/commands/dependfile') do |dependfile|
      cmd[:dependfile] ||= []
      cmd[:dependfile] << Etch.xmltext(dependfile)
    end
    Etch.xmleach(command_xml, '/commands/step') do |step_xml|
      cmd[:steps] ||= []
      step = {}
      cmd[:steps] << {step: step}
      Etch.xmleach(step_xml, 'guard/exec') do |gexec|
        step[:guard] ||= []
        step[:guard] << Etch.xmltext(gexec)
      end
      Etch.xmleach(step_xml, 'command/exec') do |cexec|
        step[:command] ||= []
        step[:command] << Etch.xmltext(cexec)
      end
    end
    cmd
  end
  def self.command_hash_to_xml(cmd, commandname)
    doc = Etch.xmlnewdoc
    root = Etch.xmlnewelem('commands', doc)
    Etch.xmlattradd(root, 'commandname', commandname)
    Etch.xmlsetroot(doc, root)
    if cmd[:depend]
      cmd[:depend].each do |depend|
        depelem = Etch.xmlnewelem('depend', doc)
        Etch.xmlsettext(depelem, depend)
        root << depelem
      end
    end
    if cmd[:dependfile]
      cmd[:dependfile].each do |dependfile|
        depelem = Etch.xmlnewelem('dependfile', doc)
        Etch.xmlsettext(depelem, dependfile)
        root << depelem
      end
    end
    if cmd[:steps]
      cmd[:steps].each do |outerstep|
        if step = outerstep[:step]
          stepelem = Etch.xmlnewelem('step', doc)
          guardelem = Etch.xmlnewelem('guard', doc)
          step[:guard] && step[:guard].each do |exec|
            execelem = Etch.xmlnewelem('exec', doc)
            Etch.xmlsettext(execelem, exec)
            guardelem << execelem
          end
          stepelem << guardelem
          commandelem = Etch.xmlnewelem('command', doc)
          step[:command] && step[:command].each do |exec|
            execelem = Etch.xmlnewelem('exec', doc)
            Etch.xmlsettext(execelem, exec)
            commandelem << execelem
          end
          stepelem << commandelem
          root << stepelem
        end
      end
    end
    doc
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
    elements.any?{|e| e != elements.first}
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
  
  def self.xmlloadstr(string)
    case Etch.xmllib
    when :libxml
      LibXML::XML::Document.string(string)
    when :nokogiri
      Nokogiri::XML(string) do |config|
        # Nokogiri is tolerant of malformed documents by default.  Good when
        # parsing HTML, but there's no reason for us to tolerate errors.  We
        # want to ensure that the user's instructions to us are clear.
        config.options = Nokogiri::XML::ParseOptions::STRICT
      end
    when :rexml
      REXML::Document.new(string)
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
      destelem.add_element(elem.deep_clone)
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
  
  def self.xmlattrvalue(elem, attrname)
    case Etch.xmllib
    when :libxml
      elem.attributes[attrname]
    when :nokogiri
      elem[attrname]
    when :rexml
      elem.attributes[attrname]
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
  # Save the original $LOAD_PATH ($:) to be restored later.
  @@load_path_org = $LOAD_PATH.clone

  def initialize(file, original_file, facts, groups, local_requests, sourcebase, commandsbase, sitelibbase, dlogger)
    # The external source is going to be processed within the same Ruby
    # instance as etch.  We want to make it clear what variables we are
    # intentionally exposing to external sources, essentially this
    # defines the "API" for those external sources.
    @file = file
    @original_file = original_file
    @facts = facts
    @groups = groups
    # In the olden days all local requests were XML snippits that the etch client
    # smashed into a single XML document to send over the wire.  This supports
    # scripts expecting the old interface.
    @local_requests = nil
    if local_requests
      @local_requests = "<requests>\n#{local_requests.join('')}\n</requests>"
    end
    # And this is a new interface where we just pass them as an array
    @local_requests_array = local_requests || []
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
    ensure
      restore_globals
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
    ensure
      restore_globals
    end
    @contents
  end

  #
  # Private subroutines
  #
  private

  # Changes made to some global variables by the external sources can cause
  # serious complications because they are executed repeatedly in a single
  # worker process.
  # We need to initialize them after each execution in order to make them
  # "to act as much like a real script as possible".
  def restore_globals
    # Restore the original $LOAD_PATH to negate any changes made.
    $LOAD_PATH.replace @@load_path_org
    # Could restore the original $LOADED_FEATURES ($"), but this worker process
    # acculumates many gems and modules over time and it's not practical to
    # reload them every time.
    # So, just deleting those in @sitelibbase or @sourcebase directory.
    $LOADED_FEATURES.reject! {|x| x.start_with?(@sitelibbase, @sourcebase)}
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

