require 'digest/sha1' # hexdigest
require 'base64'      # decode64, encode64
require 'openssl'
require 'time'        # Time.parse
require 'fileutils'   # mkdir_p
require 'logger'
require 'etch'

class Etch::Server
  DEFAULT_CONFIGBASE = '/etc/etchserver'
  
  #
  # Class methods
  #
  
  @@configbase = nil
  def self.configbase
    if !@@configbase
      if ENV['etchserverbase'] && !ENV['etchserverbase'].empty?
        @@configbase = ENV['etchserverbase']
      else
        @@configbase = DEFAULT_CONFIGBASE
      end
    end
    @@configbase
  end

  @@auth_enabled = nil
  @@auth_deny_new_clients = nil
  @@etchdebuglog = nil
  def self.read_config_file
    config_file = File.join(configbase, 'etchserver.conf')
    config_items = Hash.new(false)
    if File.exist?(config_file)
      IO.foreach(config_file) do |line|
        next if line.lstrip.first == '#'
        next unless line['=']
        k,v = line.split('=', 2).map(&:strip)
        config_items[k] = v
      end
      @@etchdebuglog = config_items['etchdebuglog'] || nil
      @@auth_enabled = config_items['auth_enabled'] == 'true'
      @@auth_deny_new_clients = config_items['auth_deny_new_clients'] == 'true'
    end
  end
  def self.auth_enabled?
    if @@auth_enabled.nil?
      read_config_file
    end
    @@auth_enabled
  end
  # How to handle new clients (allow or deny)
  def self.auth_deny_new_clients?
    if @@auth_deny_new_clients.nil?
      read_config_file
    end
    @@auth_deny_new_clients
  end
  
  # This method verifies signatures from etch clients.
  # message - the message to be verify
  # signature - the signature of the message
  # key - public key (in openssh format)
  # Currently, this only supports RSA keys.
  # Returns true if the signature is valid, false otherwise
  def self.verify_signature(message, signature, key)
    #
    # Parse through the public key to get e and m
    #
    
    str = Base64.decode64(key)
    
    # check header (this is actually the length of the key type field)
    hdr = str.slice!(0..3)
    if hdr.bytes.to_a != [0, 0, 0, 7]
      raise "Bad key format #{hdr}"
    end
    
    # check key type
    keytype = str.slice!(0..6)
    unless keytype == "ssh-rsa"
      raise "Unsupported key type #{keytype}. Only support ssh-rsa right now"
    end
    
    # get exponent
    elength = str.slice!(0..3)
    num = 0
    elength.each_byte { |x|
      num = (num << 8) +  x.to_i
    }
    elength_i = num
    
    num = 0
    e = str.slice!(0..elength_i-1)
    e.each_byte { |x|
      num = (num << 8) + x.to_i
    }
    e_i = num
    
    # get modulus
    num = 0
    nlength = str.slice!(0..3)
    nlength.each_byte { |x|
      num = (num << 8) + x.to_i
    }
    nlength_i = num
    
    num = 0
    n = str.slice!(0..nlength_i-1)
    n.each_byte { |x|
      num = (num << 8) + x.to_i
    }
    
    #
    # Create key based on e and m
    #
    
    key = OpenSSL::PKey::RSA.new
    exponent = OpenSSL::BN.new e_i.to_s
    modulus = OpenSSL::BN.new num.to_s
    key.e = exponent
    key.n = modulus
    
    #
    # Check signature
    #
    
    hash_from_sig = key.public_decrypt(Base64.decode64(signature))
    hash_from_msg =  Digest::SHA1.hexdigest(message)
    if hash_from_sig == hash_from_msg
      return true # good signature
    else
      return false # bad signature
    end
  end
  
  def self.verify_message(message, signature, params)
    timestamp = params[:timestamp]
    # Don't accept if any of the required bits are missing
    if message.nil?
      raise "message is missing"
    end
    if signature.nil?
      raise "signature is missing"
    end
    if timestamp.nil?
      raise "timestamp param is missing"
    end
    
    # Check timestamp, narrows the window of vulnerability to replay attack
    # Window is set to 5 minutes
    now = Time.new.to_i
    parsed_timestamp = Time.parse(timestamp).to_i
    timediff = now - parsed_timestamp
    if timediff.abs >= (60 * 5)
      raise "timestamp too far off (now:#{now}, timestamp:#{parsed_timestamp})"
    end
    
    # Try to find the public key
    public_key = nil
    client = Client.find_by_name(params[:fqdn])
    if client
      sshrsakey_fact = Fact.find_by_key_and_client_id('sshrsakey', client.id)
      if sshrsakey_fact
        public_key = sshrsakey_fact.value
      end
    end
    if !public_key
      if !auth_deny_new_clients? &&
         params[:facts] && params[:facts][:sshrsakey]
        # If the user has configured the server to transparently accept
        # new clients then do so, as long as the client is providing a
        # key so that we won't consider them a new client on future
        # connections. Otherwise a rogue client could continually
        # impersonate any as-yet unregistered server by supplying some
        # or all facts except the key fact.
        return true
      else
        raise "Unknown client #{params[:fqdn]}, server configured to reject unknown clients"
      end
    end
    
    # Check signature
    verify_signature(message, signature, public_key)
  end
  
  #
  # Instance methods
  #
  
  # FIXME: Should some or all of this move to the controller?
  
  def initialize(facts, tag=nil, debug=false)
    @facts = facts
    @tag = tag
    @debug = debug

    if @@etchdebuglog
      @dlogger = Logger.new(@@etchdebuglog)
    else
      @dlogger = Logger.new(File.join(Rails.root, 'log', 'etchdebug.log'))
    end

    if debug
      @dlogger.level = Logger::DEBUG
    else
      @dlogger.level = Logger::INFO
    end

    @fqdn = @facts['fqdn']

    if !@fqdn
      raise "fqdn fact not supplied"
    end

    # Update the stored facts for this client
    @client = Client.find_or_create_by(name: @fqdn)
    @facts.each do |key, value|
      fact = Fact.find_or_create_by(:client_id => @client.id, :key => key.dup) do |f|
        f.value = value
      end
      if fact.value != value
        fact.update_attributes(:value => value)
      end
    end
    Fact.where(client_id: @client.id).each do |fact|
      if !@facts.has_key?(fact.key)
        fact.destroy
      end
    end
    
    @configbase = Etch::Server.configbase
    @dlogger.debug "Using #{@configbase} as config base for node #{@fqdn}"
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
      @dlogger.debug "Tag for node #{@fqdn} supplied by client: #{@tag}"
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
      @dlogger.debug "Tag for node #{@fqdn} from external node tagger: '#{@tag}'"
    end

    @tagbase = File.join(@configbase, @tag)
    @dlogger.debug "Using #{@tagbase} as tagged base for node #{@fqdn}"
    if !File.directory?(@tagbase)
      raise "Tagged base #{@tagbase} doesn't exist"
    end

    @origbase          = "#{@configbase}/orig"
  end

  def generate(files, commands)
    #
    # Build up a list of files to generate, either from the request or from
    # the source repository if the request is for all files
    #

    request = {}
    
    # Store any original files and sums the client sent us
    if !File.directory?(@origbase)
      Dir.mkdir(@origbase, 0755)
    end
    files.each do |name, filehash|
      next if name == 'GENERATEALL'
      request[:files] = {} if !request[:files]
      request[:files][name] = {}
      if filehash['contents']
        contents = Base64.decode64(filehash['contents'])
      
        # Checksum the contents
        sha1 = Digest::SHA1.hexdigest(contents)
    
        # Compare our checksum with the one generated on the client
        if (sha1 != filehash['sha1sum'])
          raise "Calculated SHA1 sum for #{name} doesn't match client's SHA1 sum"
        end
    
        # Store the contents
        @dlogger.debug "Storing original contents for #{name}"
        origdir = "#{@origbase}/#{name}.ORIG"
        if !File.directory?(origdir)
          FileUtils.mkdir_p(origdir)
        end
        origpath = "#{origdir}/#{sha1}"
        # Note that we write in binary mode because "contents" will have an
        # "ASCII-8BIT" (aka binary) encoding, and indeed may well contain data
        # that would not be valid UTF-8.  If we don't use the binary flag to
        # open then Ruby will attempt to interpret the data as UTF-8, which
        # may well fail.
        File.open(origpath, 'wb', 0600) do |origfile|
          origfile.write(contents)
        end
        request[:files][name][:orig] = origpath
        # Update the stored record of the original
        original = Original.find_or_create_by(:client_id => @client.id, :file => name.dup) do |o|
          o.sum = sha1
        end
        if original.sum != sha1
          original.update_attributes(:sum => sha1)
        end
      end
      if filehash['sha1sum']
        sha1 = filehash['sha1sum']
        # Update the stored record of the original
        original = Original.find_or_create_by(:client_id => @client.id, :file => name.dup) do |o|
          o.sum = sha1
        end
        if original.sum != sha1
          original.update_attributes(:sum => sha1)
        end
        origdir = "#{@origbase}/#{name}.ORIG"
        origpath = "#{origdir}/#{sha1}"
        if File.exist?(origpath)
          request[:files][name][:orig] = origpath
        end
      end
      if filehash['local_requests']
        request[:files][name][:local_requests] = filehash['local_requests']
      end
    end
    
    commands.each_key do |commandname|
      request[:commands] = {} if !request[:commands]
      request[:commands][commandname] = {}
    end
    
    #
    # Process the user's request
    #
    
    etch = Etch.new(Rails.logger, @dlogger)
    response = etch.generate(@tagbase, @facts, request)
    
    #
    # Assemble our response to the client and return it
    #
    
    # Generate the XML document to return to the client
    response_xml = Etch.xmlnewdoc
    responseroot = Etch.xmlnewelem('files', response_xml)
    Etch.xmlsetroot(response_xml, responseroot)
    # Add configs for files we generated
    if response[:configs]
      configs_xml = Etch.xmlnewelem('configs', response_xml)
      response[:configs].each do |file, config_xml|
        # Update the stored record of the config
        # Exclude configs which correspond to files for which we're requesting
        # an orig.  In that case any config is just a partial config with
        # setup and depend elements that we send to the client to ensure it
        # supplies a proper orig file.
        if !response[:need_orig][file]
          configstr = config_xml.to_s
          config = EtchConfig.find_or_create_by(:client_id => @client.id, :file => file.dup) do |c|
            c.config = configstr
          end
          config.update_attributes(config: configstr)
        end
        # And add the config to the response to return to the client
        Etch.xmlcopyelem(Etch.xmlroot(config_xml), configs_xml)
      end
      responseroot << configs_xml
    end
    # Add the files for which we need original sums or contents
    if response[:need_orig]
      need_sum = []
      need_orig = []
      response[:need_orig].each_key do |need|
        # If the client already sent us the sum then we must be missing the
        # orig contents, otherwise start by requesting the sum.
        if files[need] && files[need]['sha1sum']
          need_orig << need
        else
          need_sum << need
        end
      end
      if !need_sum.empty?
        need_sums_xml = Etch.xmlnewelem('need_sums', response_xml)
        need_sum.each do |need|
          need_xml = Etch.xmlnewelem('need_sum', response_xml)
          Etch.xmlsettext(need_xml, need)
          need_sums_xml << need_xml
        end
        responseroot << need_sums_xml
      end
      if !need_orig.empty?
        need_origs_xml = Etch.xmlnewelem('need_origs', response_xml)
        need_orig.each do |need|
          need_xml = Etch.xmlnewelem('need_orig', response_xml)
          Etch.xmlsettext(need_xml, need)
          need_origs_xml << need_xml
        end
        responseroot << need_origs_xml
      end
    end
    # Add commands we generated
    # The root XML element in each commands.xml is already the plural
    # "commands", so we have to use something different here as the XML
    # element we insert all of those into as part of the response.
    if response[:allcommands]
      commands_xml = Etch.xmlnewelem('allcommands', response_xml)
      response[:allcommands].each do |commandname, command_xml|
        # Update the stored record of the command
        commandstr = command_xml.to_s
        config = EtchConfig.find_or_create_by(:client_id => @client.id, :file => commandname.dup) do |c|
          c.config = commandstr
        end
        config.update_attributes(config: commandstr)
        # Add the command to the response to return to the client
        Etch.xmlcopyelem(Etch.xmlroot(command_xml), commands_xml)
      end
      responseroot << commands_xml
    end
    if response[:retrycommands]
      retrycommands_xml = Etch.xmlnewelem('retrycommands', response_xml)
      response[:retrycommands].each_key do |commandname|
        retry_xml = Etch.xmlnewelem('retrycommand', response_xml)
        Etch.xmlsettext(retry_xml, commandname)
        retrycommands_xml << retry_xml
      end
      responseroot << retrycommands_xml
    end
    
    # Clean up XML formatting
    # But only if we're in debug mode, in regular mode nobody but the
    # machines will see the XML and they don't care if it is pretty.
    # FIXME: Tidy's formatting breaks things, it inserts leading/trailing whitespace into text nodes
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

    @dlogger.debug "Returning #{response_xml}"
    response_xml
  end
end

