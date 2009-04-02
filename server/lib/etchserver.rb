require 'find'
require 'pathname'    # absolute?
require 'digest/sha1' # hexdigest
require 'base64'      # decode64, encode64
require 'fileutils'   # mkdir_p
require 'libxml'
require 'erb'
require 'versiontype' # Version

module Etch
end

class Etch::Server
  def initialize(facts, tag=nil, debug=false)
    @facts = facts
    @tag = tag
    @debug = debug

    @fqdn = @facts['fqdn']
    if !@fqdn
      raise "fqdn fact not supplied"
    end

    # Update the stored facts for this client
    @client = Client.find_or_create_by_name(@fqdn)
    @facts.each do |key, value|
      fact = Fact.find_or_create_by_client_id_and_key(:client_id => @client.id, :key => key, :value => value)
      if fact.value != value
        fact.update_attributes(:value => value)
      end
    end
    Fact.find_all_by_client_id(@client.id).each do |fact|
      if !@facts.has_key?(fact.key)
        fact.destroy
      end
    end

    if ENV['etchserverbase'] && !ENV['etchserverbase'].empty?
      @configbase = ENV['etchserverbase']
    else
      @configbase = '/etc/etchserver'
    end
    RAILS_DEFAULT_LOGGER.info "Using #{@configbase} as config base for node #{@fqdn}" if (@debug)
    if !File.directory?(@configbase)
      raise "Config base #{@configbase} doesn't exist"
    end
    
    # Check for killswitch
    killswitch = File.join(@configbase, 'killswitch')
    if File.exist?(killswitch)
      contents = IO.read(killswitch)
      raise "killswitch activated: #{contents}"
    end
    
    # Run the external node tagger
    # A client-supplied tag overrides the server-side node tagger
    if !@tag.nil? && !@tag.empty?
      # Don't allow the client to slip us a funky tag (i.e. '../../../etc' or something)
      if @tag.include?('..')
        raise "Client supplied tag #{@tag} contains '..'"
      end
      RAILS_DEFAULT_LOGGER.info "Tag for node #{@fqdn} supplied by client: #{@tag}" if (@debug)
    else
      IO.popen(File.join(@configbase, 'nodetagger') + ' ' + @fqdn) do |pipe|
        tmptag = pipe.gets
        if tmptag.nil?
          @tag = ''
        else
          @tag = tmptag.chomp
        end
      end
      if !$?.success?
        raise "External node tagger exited with error #{$?.exitstatus}"
      end
      RAILS_DEFAULT_LOGGER.info "Tag for node #{@fqdn} from external node tagger: '#{@tag}'" if (@debug)
    end

    @tagbase = File.join(@configbase, @tag)
    RAILS_DEFAULT_LOGGER.info "Using #{@tagbase} as tagged base for node #{@fqdn}" if (@debug)
    if !File.directory?(@tagbase)
      raise "Tagged base #{@tagbase} doesn't exist"
    end

    # Set up all the variables that point to various directories within our
    # base directory.
    @sourcebase      = "#{@tagbase}/source"
    @sitelibbase     = "#{@tagbase}/sitelibs"
    @config_dtd_file = "#{@tagbase}/config.dtd"
    @defaults_file   = "#{@tagbase}/defaults.xml"
    @nodes_file      = "#{@tagbase}/nodes.xml"
    @nodegroups_file = "#{@tagbase}/nodegroups.xml"
    @origbase        = "#{@configbase}/orig"
    
    #
    # Load the DTD which is used to validate config.xml files
    #
    @config_dtd = LibXML::XML::Dtd.new(IO.read(@config_dtd_file))
    
    #
    # Load the defaults.xml file which sets defaults for parameters that the
    # user doesn't specify in his config.xml files.
    #
    
    @defaults_xml = LibXML::XML::Document.file(@defaults_file)
    
    #
    # Load the nodes file
    #

    @nodes_xml = LibXML::XML::Document.file(@nodes_file)
    # Extract the groups for this node
    thisnodeelem = @nodes_xml.find_first("/nodes/node[@name='#{@fqdn}']")
    groupshash = {}
    if thisnodeelem
      thisnodeelem.find('group').each { |group| groupshash[group.content] = true }
    else
      RAILS_DEFAULT_LOGGER.info "No entry found for node #{@fqdn} in nodes.xml" if (@debug)
      # Some folks might want to terminate here
      #raise "No entry found for node #{@fqdn} in nodes.xml"
    end
    RAILS_DEFAULT_LOGGER.info "Native groups for node #{@fqdn}: #{groupshash.keys.sort.join(',')}" if (@debug)

    #
    # Load the node groups file
    #

    @nodegroups_xml = LibXML::XML::Document.file(@nodegroups_file)

    # Extract the node group hierarchy into a hash for easy reference
    @group_hierarchy = {}
    @nodegroups_xml.find('/nodegroups/nodegroup').each do |parent|
      parent.find('child').each do |child|
        @group_hierarchy[child.content] = [] if !@group_hierarchy[child.content]
        @group_hierarchy[child.content] << parent.attributes['name']
      end
    end

    # Fill out the list of groups for this node with any parent groups
    parentshash = {}
    groupshash.keys.each do |group|
      parents = get_parent_nodegroups(group)
      parents.each { |parent| parentshash[parent] = true }
    end
    parentshash.keys.each { |parent| groupshash[parent] = true }
    RAILS_DEFAULT_LOGGER.info "Added groups for node #{@fqdn} due to node group hierarchy: #{parentshash.keys.sort.join(',')}" if (@debug)

    # Run the external node grouper
    externalhash = {}
    IO.popen(File.join(@tagbase, 'nodegrouper') + ' ' + @fqdn) do |pipe|
      pipe.each { |group| externalhash[group.chomp] = true }
    end
    if !$?.success?
      raise "External node grouper exited with error #{$?.exitstatus}"
    end
    externalhash.keys.each { |external| groupshash[external] = true }
    RAILS_DEFAULT_LOGGER.info "Added groups for node #{@fqdn} due to external node grouper: #{externalhash.keys.sort.join(',')}" if (@debug)

    @groups = groupshash.keys.sort
    RAILS_DEFAULT_LOGGER.info "Total groups for node #{@fqdn}: #{@groups.join(',')}" if (@debug)
  end

  def generate(files)
    #
    # Build up a list of files to generate, either from the request or from
    # the source repository if the request is for all files
    #

    filelist = []
    if files['GENERATEALL']
      RAILS_DEFAULT_LOGGER.info "Building file list for GENERATEALL request from #{@fqdn}" if (@debug)
      Find.find(@sourcebase) do |path|
        if File.directory?(path) && File.exist?(File.join(path, 'config.xml'))
          # Strip @sourcebase from start of path
          filelist << path.gsub(Regexp.new('^' + Regexp.escape(@sourcebase)), '')
        end
      end
    else
      RAILS_DEFAULT_LOGGER.info "Building file list based on request for specific files from #{@fqdn}" if (@debug)
      filelist = files.keys
    end
    RAILS_DEFAULT_LOGGER.info "Generating #{filelist.length} files" if (@debug)

    # Store any original files and sums the client sent us
    if !File.directory?(@origbase)
      Dir.mkdir(@origbase, 0755)
    end
    files.each do |name, filehash|
      if filehash['contents']
        contents = Base64.decode64(filehash['contents'])
        
        # Checksum the contents
        sha1 = Digest::SHA1.hexdigest(contents)
      
        # Compare our checksum with the one generated on the client
        if (sha1 != filehash['sha1sum'])
          raise "Calculated SHA1 sum for #{name} doesn't match client's SHA1 sum"
        end
      
        # Store the contents
        RAILS_DEFAULT_LOGGER.info "Storing original contents for #{name}" if (@debug)
        origdir = "#{@origbase}/#{name}.ORIG"
        if !File.directory?(origdir)
          FileUtils.mkdir_p(origdir)
        end
        File.open("#{origdir}/#{sha1}", 'w', 0400) do |origfile|
          origfile.write(contents)
        end
        # Update the stored record of the original
        original = Original.find_or_create_by_client_id_and_file(:client_id => @client.id, :file => name, :sum => sha1)
        if original.sum != sha1
          original.update_attributes(:sum => sha1)
        end
      end
      if filehash['sha1sum']
        sha1 = filehash['sha1sum']
        # Update the stored record of the original
        original = Original.find_or_create_by_client_id_and_file(:client_id => @client.id, :file => name, :sum => sha1)
        if original.sum != sha1
          original.update_attributes(:sum => sha1)
        end
      end
    end

    #
    # Loop over each file in the request and generate it
    #
  
    @filestack = {}
    @already_generated = {}
    @generation_status = {}
    @configs = {}
    @need_sum = {}
    @need_orig = {}

    filelist.each do |file|
      RAILS_DEFAULT_LOGGER.info "Generating #{file}" if @debug
      generate_file(file, files)
    end

    # Generate the XML document to return to the client
    response_xml = LibXML::XML::Document.new
    response_xml.root = LibXML::XML::Node.new('files')
    # Add configs for files we generated
    configs_xml = LibXML::XML::Node.new('configs')
    @configs.each do |file, config_xml|
      # Update the stored record of the config
      # Exclude configs which correspond to files for which we're
      # requesting a sum or orig.  In that case any config is just a
      # partial config with setup and depend elements that we send to
      # the client to ensure it supplies a proper orig file.
      if !@need_sum.has_key?(file) && !@need_orig.has_key?(file)
        config = EtchConfig.find_or_create_by_client_id_and_file(:client_id => @client.id, :file => file, :config => config_xml.to_s)
        if config.config != config_xml.to_s
          config.update_attributes(:config => config_xml.to_s)
        end
      end
      # And add the config to the response to return to the client
      configs_xml << config_xml.root.copy(true)
    end
    response_xml.root << configs_xml
    # Add the files for which we need sums
    need_sums_xml = LibXML::XML::Node.new('need_sums')
    @need_sum.each_key do |need|
      need_xml = LibXML::XML::Node.new('need_sum')
      need_xml.content = need
      need_sums_xml << need_xml
    end
    response_xml.root << need_sums_xml
    # Add the files for which we need originals
    need_origs_xml = LibXML::XML::Node.new('need_origs')
    @need_orig.each_key do |need|
      need_xml = LibXML::XML::Node.new('need_orig')
      need_xml.content = need
      need_origs_xml << need_xml
    end
    response_xml.root << need_origs_xml
    
    # FIXME: clean up XML formatting
    # But only if we're in debug mode, in regular mode nobody but the
    # machines will see the XML and they don't care if it is pretty.
    # Tidy's formatting breaks things, it inserts leading/trailing whitespace into text nodes
    if @debug && false
      require 'tidy'
      Tidy.path = '/sw/lib/libtidy.dylib'
      Tidy.open(:show_warnings=>true) do |tidy|
        tidy.options.input_xml = true
        tidy.options.output_xml = true
        # Screws up the Base64 contents data
        #tidy.options.indent = true
        tidy.options.hide_comments = true
        response_xml = tidy.clean(response_xml.to_s)
        puts tidy.errors
        puts tidy.diagnostics if (@debug)
      end
    end

    RAILS_DEFAULT_LOGGER.info "Returning #{response_xml}" if @debug
    response_xml
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

  def generate_file(file, files)
    # Skip files we've already generated in response to <depend>
    # statements.
    if @already_generated[file]
      RAILS_DEFAULT_LOGGER.info "Skipping already generated #{file}" if (@debug)
      return
    end

    generation_status = true

    # Check for circular dependencies, otherwise we're vulnerable
    # to going into an infinite loop
    if @filestack[file]
      raise "Circular dependency detected for #{file}"
    end
    @filestack[file] = true
    
    # LibXML doesn't handle attempting to open a non-existent file well
    # http://rubyforge.org/tracker/index.php?func=detail&aid=23836&group_id=494&atid=1971
    config_xml_file = File.join(@sourcebase, file, 'config.xml')
    if !File.exist?(config_xml_file)
      raise "config.xml for #{file} does not exist"
    end
    
    # Load the config.xml file
    config_xml = LibXML::XML::Document.file(config_xml_file)
    
    # Filter the config.xml file by looking for attributes
    begin
      configfilter!(config_xml.root)
    rescue Exception => e
      raise e.exception("Error filtering config.xml for #{file}:\n" + e.message)
    end
    
    # Validate the filtered file against config.dtd
    if !config_xml.validate(@config_dtd)
      raise "Filtered config.xml for #{file} fails validation"
    end
    
    done = false

    # Generate any other files that this file depends on
    depends = []
    config_xml.find('/config/depend').each do |depend|
      RAILS_DEFAULT_LOGGER.info "Generating dependency #{depend.content}" if (@debug)
      depends << depend.content
      generate_file(depend.content, files)
    end
    # If any dependency failed to generate (due to a need for orig sum or
    # contents from the client) then we need to unroll the whole dependency
    # tree and punt it back to the client
    dependency_status = depends.all? { |depend| @generation_status[depend] }
    if !dependency_status
      depends.each do |depend|
        # Make sure any configuration we're returning is just the basics
        # needed to supply orig data
        if @configs[depend]
          filter_xml_completely!(@configs[depend], ['depend', 'setup'])
        end
        # And if we weren't already planning to request an orig sum or
        # contents for this file then stick it into the orig sum request
        # list so that the client knows it needs to ask for this file
        # again next time.
        if !@need_sum.has_key?(depend) && !@need_orig.has_key?(depend)
          @need_sum[depend] = true
        end
      end
      # Lastly make sure that this file gets sent back appropriately
      @need_sum[file] = true
      filter_xml_completely!(config_xml, ['depend', 'setup'])
      generation_status = false
      done = true
    end
    
    # Change into the corresponding directory so that the user can
    # refer to source files and scripts by their relative pathnames.
    Dir::chdir "#{@sourcebase}/#{file}"

    # See what type of action the user has requested

    # Check to see if the user has requested that we revert back to the
    # original file.
    if config_xml.find_first('/config/revert') && !done
      # Pass the revert action back to the client
      filter_xml!(config_xml, ['revert'])
      done = true
    end
  
    # Perform any server setup commands
    if config_xml.find_first('/config/server_setup') && !done
      RAILS_DEFAULT_LOGGER.info "Processing server setup commands" if (@debug)
      config_xml.find('/config/server_setup/exec').each do |cmd|
        RAILS_DEFAULT_LOGGER.info "  Executing #{cmd.content}" if (@debug)
        success = system(cmd.content)
        if !success
          raise "Server setup command #{cmd.content} for file #{file} exited with non-zero value"
        end
      end
    end
  
    # Make sure we have the original contents for this file
    original_file = nil
    if !files[file] || !files[file]['sha1sum']
      @need_sum[file] = true
      # If there are setup commands defined for this file we need to
      # pass those back along with our request for the original file,
      # as the setup commands may be needed to create the original
      # file on the node.
      filter_xml_completely!(config_xml, ['depend', 'setup'])
      # Nothing more can be done until we have the original file from
      # the client
      generation_status = false
      done = true
    else
      original_file = "#{@origbase}/#{file}.ORIG/#{files[file]['sha1sum']}"
      if !File.exist?(original_file) && !done
        @need_orig[file] = true
        # If there are setup commands defined for this file we need to
        # pass those back along with our request for the original file,
        # as the setup commands may be needed to create the original
        # file on the node.
        filter_xml_completely!(config_xml, ['depend', 'setup'])
        # Nothing more can be done until we have the original file from
        # the client
        generation_status = false
        done = true
      end
    end
  
    #
    # Regular file
    #

    if config_xml.find_first('/config/file') && !done
      #
      # Assemble the contents for the file
      #
      newcontents = ''
      
      if config_xml.find_first('/config/file/source/plain')
        plain_elements = config_xml.find('/config/file/source/plain').to_a
        if check_for_inconsistency(plain_elements)
          raise "Inconsistent 'plain' entries for #{file}"
        end
        
        # Just slurp the file in
        plain_file = plain_elements.first.content
        newcontents = IO::read(plain_file)
      elsif config_xml.find_first('/config/file/source/template')
        template_elements = config_xml.find('/config/file/source/template').to_a
        if check_for_inconsistency(template_elements)
          raise "Inconsistent 'template' entries for #{file}"
        end
        
        # Run the template through ERB to generate the file contents
        template = template_elements.first.content
        external = EtchExternalSource.new(file, original_file, @facts, @groups, @sourcebase, @sitelibbase, @debug)
        newcontents = external.process_template(template)
      elsif config_xml.find_first('/config/file/source/script')
        script_elements = config_xml.find('/config/file/source/script').to_a
        if check_for_inconsistency(script_elements)
          raise "Inconsistent 'script' entries for #{file}"
        end
        
        # Run the script to generate the file contents
        script = script_elements.first.content
        external = EtchExternalSource.new(file, original_file, @facts, @groups, @sourcebase, @sitelibbase, @debug)
        newcontents = external.run_script(script)
      elsif config_xml.find_first('/config/file/always_manage_metadata')
        # always_manage_metadata is a special case where we proceed
        # even if we don't have any source for file contents.
      else
        # If the filtering has removed the source for this file's
        # contents, that means it doesn't apply to this node.
        RAILS_DEFAULT_LOGGER.info "No configuration for file #{file} contents, doing nothing" if (@debug)
        
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
          ! config_xml.find_first('/config/file/allow_empty') &&
          ! config_xml.find_first('/config/file/always_manage_metadata')
        RAILS_DEFAULT_LOGGER.info "New contents for file #{file} empty, doing nothing" if (@debug)
      else
        # Finish assembling the file contents as long as we're not
        # proceeding based only on always_manage_metadata.  If we are
        # proceeding based only on always_manage_metadata we want to make
        # sure that the only action we'll take is to manage metadata, not
        # muck with the file's contents.
        if !(newcontents == '' && config_xml.find_first('/config/file/always_manage_metadata'))
          # Add the warning message (if defined)
          warning_file = nil
          if config_xml.find_first('/config/file/warning_file')
            if !config_xml.find_first('/config/file/warning_file').content.empty?
              warning_file = config_xml.find_first('/config/file/warning_file').content
            end
          elsif @defaults_xml.find_first('/config/file/warning_file')
            if !@defaults_xml.find_first('/config/file/warning_file').content.empty?
              warning_file = @defaults_xml.find_first('/config/file/warning_file').content
            end
          end
          if warning_file
            warning = ''

            # First the comment opener
            comment_open = nil
            if config_xml.find_first('/config/file/comment_open')
              comment_open = config_xml.find_first('/config/file/comment_open').content
            elsif @defaults_xml.find_first('/config/file/comment_open')
              comment_open = @defaults_xml.find_first('/config/file/comment_open').content
            end
            if comment_open && !comment_open.empty?
              warning << comment_open << "\n"
            end

            # Then the message
            comment_line = '# '
            if config_xml.find_first('/config/file/comment_line')
              comment_line = config_xml.find_first('/config/file/comment_line').content
            elsif @defaults_xml.find_first('/config/file/comment_line')
              comment_line = @defaults_xml.find_first('/config/file/comment_line').content
            end

            warnpath = Pathname.new(warning_file)
            if !File.exist?(warning_file) && !warnpath.absolute?
              warning_file = File.expand_path(warning_file, @tagbase)
            end

            File.open(warning_file) do |warnfile|
              while line = warnfile.gets
                warning << comment_line << line
              end
            end

            # And last the comment closer
            comment_close = nil
            if config_xml.find_first('/config/file/comment_close')
              comment_close = config_xml.find_first('/config/file/comment_close').content
            elsif @defaults_xml.find_first('/config/file/comment_close')
              comment_close = @defaults_xml.find_first('/config/file/comment_close').content
            end
            if comment_close && !comment_close.empty?
              warning << comment_close << "\n"
            end

            # By default we insert the warning at the top of the
            # generated file.  However, some files (particularly
            # scripts) have a special first line.  The user can flag
            # those files to have the warning inserted starting at the
            # second line.
            if !config_xml.find_first('/config/file/warning_on_second_line')
              # And then other files (notably Solaris crontabs) can't
              # have any blank lines.  Normally we insert a blank
              # line between the warning message and the generated
              # file to improve readability.  The user can flag us to
              # not insert that blank line.
              if !config_xml.find_first('/config/file/no_space_around_warning')
                newcontents = warning + "\n" + newcontents
              else
                newcontents = warning + newcontents
              end
            else
              parts = newcontents.split("\n", 2)
              if !config_xml.find_first('/config/file/no_space_around_warning')
                newcontents = parts[0] << "\n\n" << warning << "\n" << parts[1]
              else
                newcontents = parts[0] << warning << parts[1]
              end
            end
          end # if warning_file
    
          # Add the generated file contents to the XML
          contentselem = LibXML::XML::Node.new('contents')
          contentselem.content = Base64.encode64(newcontents)
          config_xml.find_first('/config/file') << contentselem
        end

        # Remove the source configuration from the XML, the
        # client won't need to see it
        config_xml.find('/config/file/source').each { |elem| elem.remove! }

        # Remove all of the warning related elements from the XML, the
        # client won't need to see them
        config_xml.find('/config/file/warning_file').each { |elem| elem.remove! }
        config_xml.find('/config/file/warning_on_second_line').each { |elem| elem.remove! }
        config_xml.find('/config/file/no_space_around_warning').each { |elem| elem.remove! }
        config_xml.find('/config/file/comment_open').each { |elem| elem.remove! }
        config_xml.find('/config/file/comment_line').each { |elem| elem.remove! }
        config_xml.find('/config/file/comment_close').each { |elem| elem.remove! }
        
        # If the XML doesn't contain ownership and permissions entries
        # then add appropriate ones based on the defaults
        if !config_xml.find_first('/config/file/owner')
          if @defaults_xml.find_first('/config/file/owner')
            config_xml.find_first('/config/file') << @defaults_xml.find_first('/config/file/owner').copy(true)
          else
            raise "defaults.xml needs /config/file/owner"
          end
        end
        if !config_xml.find_first('/config/file/group')
          if @defaults_xml.find_first('/config/file/group')
            config_xml.find_first('/config/file') << @defaults_xml.find_first('/config/file/group').copy(true)
          else
            raise "defaults.xml needs /config/file/group"
          end
        end
        if !config_xml.find_first('/config/file/perms')
          if @defaults_xml.find_first('/config/file/perms')
            config_xml.find_first('/config/file') << @defaults_xml.find_first('/config/file/perms').copy(true)
          else
            raise "defaults.xml needs /config/file/perms"
          end
        end
      
        # Send the file contents and metadata to the client
        filter_xml!(config_xml, ['file'])
      
        done = true
      end
    end

    #
    # Symbolic link
    #
  
    if config_xml.find_first('/config/link') && !done
      dest = nil
    
      if config_xml.find_first('/config/link/dest')
        dest_elements = config_xml.find('/config/link/dest').to_a
        if check_for_inconsistency(dest_elements)
          raise "Inconsistent 'dest' entries for #{file}"
        end
      
        dest = dest_elements.first.content
      elsif config_xml.find_first('/config/link/script')
        # The user can specify a script to perform more complex
        # testing to decide whether to create the link or not and
        # what its destination should be.
        
        script_elements = config_xml.find('/config/link/script').to_a
        if check_for_inconsistency(script_elements)
          raise "Inconsistent 'script' entries for #{file}"
        end
        
        script = script_elements.first.content
        external = EtchExternalSource.new(file, original_file, @facts, @groups, @sourcebase, @sitelibbase, @debug)
        dest = external.run_script(script)
        
        # Remove the script element(s) from the XML, the client won't need
        # to see them
        script_elements.each { |se| se.remove! }
      else
        # If the filtering has removed the destination for the link,
        # that means it doesn't apply to this node.
        RAILS_DEFAULT_LOGGER.info "No configuration for link #{file} destination, doing nothing" if (@debug)
      end

      if !dest || dest.empty?
        RAILS_DEFAULT_LOGGER.info "Destination for link #{file} empty, doing nothing" if (@debug)
      else
        # If there isn't a dest element in the XML (if the user used a
        # script) then insert one for the benefit of the client
        if !config_xml.find_first('/config/link/dest')
          destelem = LibXML::XML::Node.new('dest')
          destelem.content = dest
          config_xml.find_first('/config/link') << destelem
        end

        # If the XML doesn't contain ownership and permissions entries
        # then add appropriate ones based on the defaults
        if !config_xml.find_first('/config/link/owner')
          if @defaults_xml.find_first('/config/link/owner')
            config_xml.find_first('/config/link') << @defaults_xml.find_first('/config/link/owner').copy(true)
          else
            raise "defaults.xml needs /config/link/owner"
          end
        end
        if !config_xml.find_first('/config/link/group')
          if @defaults_xml.find_first('/config/link/group')
            config_xml.find_first('/config/link') << @defaults_xml.find_first('/config/link/group').copy(true)
          else
            raise "defaults.xml needs /config/link/group"
          end
        end
        if !config_xml.find_first('/config/link/perms')
          if @defaults_xml.find_first('/config/link/perms')
            config_xml.find_first('/config/link') << @defaults_xml.find_first('/config/link/perms').copy(true)
          else
            raise "defaults.xml needs /config/link/perms"
          end
        end
      
        # Send the file contents and metadata to the client
        filter_xml!(config_xml, ['link'])

        done = true
      end
    end

    #
    # Directory
    #
  
    if config_xml.find_first('/config/directory') && !done
      create = false
      if config_xml.find_first('/config/directory/create')
        create = true
      elsif config_xml.find_first('/config/directory/script')
        # The user can specify a script to perform more complex testing
        # to decide whether to create the directory or not.
        script_elements = config_xml.find('/config/directory/script').to_a
        if check_for_inconsistency(script_elements)
          raise "Inconsistent 'script' entries for #{file}"
        end
        
        script = script_elements.first.content
        external = EtchExternalSource.new(file, original_file, @facts, @groups, @sourcebase, @sitelibbase, @debug)
        create = external.run_script(script)
        create = false if create.empty?
        
        # Remove the script element(s) from the XML, the client won't need
        # to see them
        script_elements.each { |se| se.remove! }
      else
        # If the filtering has removed the directive to create this
        # directory, that means it doesn't apply to this node.
        RAILS_DEFAULT_LOGGER.info "No configuration to create directory #{file}, doing nothing" if (@debug)
      end
    
      if !create
        RAILS_DEFAULT_LOGGER.info "Directive to create directory #{file} false, doing nothing" if (@debug)
      else
        # If there isn't a create element in the XML (if the user used a
        # script) then insert one for the benefit of the client
        if !config_xml.find_first('/config/directory/create')
          createelem = LibXML::XML::Node.new('create')
          config_xml.find_first('/config/directory') << createelem
        end

        # If the XML doesn't contain ownership and permissions entries
        # then add appropriate ones based on the defaults
        if !config_xml.find_first('/config/directory/owner')
          if @defaults_xml.find_first('/config/directory/owner')
            config_xml.find_first('/config/directory') << @defaults_xml.find_first('/config/directory/owner').copy(true)
          else
            raise "defaults.xml needs /config/directory/owner"
          end
        end
        if !config_xml.find_first('/config/directory/group')
          if @defaults_xml.find_first('/config/directory/group')
            config_xml.find_first('/config/directory') << @defaults_xml.find_first('/config/directory/group').copy(true)
          else
            raise "defaults.xml needs /config/directory/group"
          end
        end
        if !config_xml.find_first('/config/directory/perms')
          if @defaults_xml.find_first('/config/directory/perms')
            config_xml.find_first('/config/directory') << @defaults_xml.find_first('/config/directory/perms').copy(true)
          else
            raise "defaults.xml needs /config/directory/perms"
          end
        end
      
        # Send the file contents and metadata to the client
        filter_xml!(config_xml, ['directory'])
      
        done = true
      end
    end

    #
    # Delete whatever is there
    #

    if config_xml.find_first('/config/delete') && !done
      proceed = false
      if config_xml.find_first('/config/delete/proceed')
        proceed = true
      elsif config_xml.find_first('/config/delete/script')
        # The user can specify a script to perform more complex testing
        # to decide whether to delete the file or not.
        script_elements = config_xml.find('/config/delete/script').to_a
        if check_for_inconsistency(script_elements)
          raise "Inconsistent 'script' entries for #{file}"
        end
        
        script = script_elements.first.content
        external = EtchExternalSource.new(file, original_file, @facts, @groups, @sourcebase, @sitelibbase, @debug)
        proceed = external.run_script(script)
        proceed = false if proceed.empty?
        
        # Remove the script element(s) from the XML, the client won't need
        # to see them
        script_elements.each { |se| se.remove! }
      else
        # If the filtering has removed the directive to remove this
        # file, that means it doesn't apply to this node.
        RAILS_DEFAULT_LOGGER.info "No configuration to delete #{file}, doing nothing" if (@debug)
      end
    
      if !proceed
        RAILS_DEFAULT_LOGGER.info "Directive to delete #{file} false, doing nothing" if (@debug)
      else
        # If there isn't a proceed element in the XML (if the user used a
        # script) then insert one for the benefit of the client
        if !config_xml.find_first('/config/delete/proceed')
          proceedelem = LibXML::XML::Node.new('proceed')
          config_xml.find_first('/config/delete') << proceedelem
        end

        # Send the file contents and metadata to the client
        filter_xml!(config_xml, ['delete'])
      
        done = true
      end
    end
  
    if done && config_xml.find_first('/config/*')
      # The client needs this attribute to know to which file
      # this chunk of XML refers
      config_xml.root.attributes['filename'] = file
      @configs[file] = config_xml
    end
  
    @already_generated[file] = true
    @filestack.delete(file)
    @generation_status[file] = generation_status
  end

  ALWAYS_KEEP = ['depend', 'setup', 'pre', 'test_before_post', 'post', 'test']
  def filter_xml_completely!(config_xml, keepers=[])
    remove = []
    config_xml.root.each_element do |elem|
      if !keepers.include?(elem.name)
        # remove! throws off each_element, have to save up a list of
        # elements to remove and remove them outside of the each_element
        # block
        # http://rubyforge.org/tracker/index.php?func=detail&aid=23799&group_id=494&atid=1971
        #elem.remove!
        remove << elem
      end
    end
    remove.each { |elem| elem.remove! }
    # FIXME: strip comments (tidy is doing this now...)
  end
  def filter_xml!(config_xml, keepers=[])
    filter_xml_completely!(config_xml, keepers.concat(ALWAYS_KEEP))
  end

  def configfilter!(element)
    elem_remove = []
    attr_remove = []
    element.each_element do |elem|
      catch :next_element do
        elem.attributes.each do |attribute|
          if !check_attribute(attribute.name, attribute.value)
            # Node#remove! throws off Node#each_element, so we have to save
            # up a list of elements to remove and remove them outside of
            # the each_element block
            # http://rubyforge.org/tracker/index.php?func=detail&aid=23799&group_id=494&atid=1971
            #elem.remove!
            elem_remove << elem
            throw :next_element
          else
            # Same deal with Attr#remove! and Attributes#each
            # http://rubyforge.org/tracker/index.php?func=detail&aid=23829&group_id=494&atid=1971
            #attribute.remove!
            attr_remove << attribute
          end
        end
        # Then check any children of this element
        configfilter!(elem)
      end
    end
    elem_remove.each { |elem| elem.remove! }
    attr_remove.each { |attribute| attribute.remove! }
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
    elements_as_text = elements.collect { |elem| elem.content }
    if elements_as_text.uniq.length != 1
      return true
    else
      return false
    end
  end

end

class EtchExternalSource
  def initialize(file, original_file, facts, groups, sourcebase, sitelibbase, debug=false)
    # The external source is going to be processed within the same Ruby
    # instance as etch.  We want to make it clear what variables we are
    # intentionally exposing to external sources, essentially this
    # defines the "API" for those external sources.
    @file = file
    @original_file = original_file
    @facts = facts
    @groups = groups
    @sourcebase = sourcebase
    @sitelibbase = sitelibbase
    @debug = debug
  end

  # This method processes an ERB template (as specified via a <template>
  # entry in a config.xml file) and returns the results.
  def process_template(template)
    RAILS_DEFAULT_LOGGER.info "Processing template #{template} for file #{@file}" if (@debug)
    # The '-' arg allows folks to use <% -%> or <%- -%> to instruct ERB to
    # not insert a newline for that line, which helps avoid a bunch of blank
    # lines in the processed file where there was code in the template.
    erb = ERB.new(IO.read(template), nil, '-')
    # The binding arg ties the template's namespace to this point in the
    # code, thus ensuring that all of the variables above (@file, etc.)
    # are visible to the template code.
    erb.result(binding)
  end

  # This method runs a etch script (as specified via a <script> entry
  # in a config.xml file) and returns any output that the script puts in
  # the @contents variable.
  def run_script(script)
    RAILS_DEFAULT_LOGGER.info "Processing script #{script} for file #{@file}" if (@debug)
    @contents = ''
    begin
      eval(IO.read(script))
    rescue Exception => e
      if e.kind_of?(SystemExit)
        # The user might call exit within a script.  We want the scripts
        # to act as much like a real script as possible, so ignore those.
      else
        # Help the user figure out where the exception occurred, otherwise they
        # just get told it happened here in eval, which isn't very helpful.
        raise e.exception("Exception while processing script #{script} for file #{@file}:\n" + e.message)
      end
    end
    @contents
  end
end

