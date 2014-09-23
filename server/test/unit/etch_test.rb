require 'test_helper'
require 'etch'

# Unit tests for lib/etch.rb

class EtchTest < ActiveSupport::TestCase
  def setup
    logger = Logger.new(STDOUT)
    # dlogger = Logger.new(STDOUT)
    dlogger = Logger.new('/dev/null')
    @etch = Etch.new(logger, dlogger)
    @configdir = Dir.mktmpdir
    @etch.instance_variable_set(:@configdir, @configdir)
    @etch.instance_variable_set(:@sourcebase, "#{@configdir}/source")
    @etch.instance_variable_set(:@commandsbase, "#{@configdir}/commands")
    @etch.instance_variable_set(:@config_dtd, Etch.xmlloaddtd("#{File.dirname(__FILE__)}/../../../test/testrepo/config.dtd"))
    @etch.instance_variable_set(:@commands_dtd, Etch.xmlloaddtd("#{File.dirname(__FILE__)}/../../../test/testrepo/commands.dtd"))
  end
  test 'load defaults yaml empty' do
    File.open("#{@configdir}/defaults.yml", 'w') do |file|
      file.puts 'file: {}'
    end
    defaults = @etch.send :load_defaults
    assert_equal({file: {}, link: {}, directory: {}}, defaults)
  end
  test 'load defaults yaml' do
    File.open("#{@configdir}/defaults.yml", 'w') do |file|
      file.write <<EOF
file:
  owner: 0
EOF
    end
    defaults = @etch.send :load_defaults
    assert_equal(0, defaults[:file][:owner])
    assert_equal({}, defaults[:link])
  end
  test 'load defaults xml empty' do
    File.open("#{@configdir}/defaults.xml", 'w') do |file|
    end
    defaults = @etch.send :load_defaults
    assert_equal({file: {}, link: {}, directory: {}}, defaults)
  end
  test 'load default xml' do
    File.open("#{@configdir}/defaults.xml", 'w') do |file|
      file.write <<-EOF
      <config>
        <file>
          <owner>1</owner>
          <warning_file>warning.txt</warning_file>
          <comment_line># </comment_line>
        </file>
      </config>
      EOF
    end
    defaults = @etch.send :load_defaults
    assert_equal(1, defaults[:file][:owner])
    assert_equal('warning.txt', defaults[:file][:warning_file])
    assert_equal('# ', defaults[:file][:comment_line])
    assert_equal({}, defaults[:link])
  end
  test 'symbolize_etch_key' do
    key = 'plain'
    assert_equal(key.to_sym, @etch.send(:symbolize_etch_key, key))
    key = 'whereplain'
    assert_equal(key.to_sym, @etch.send(:symbolize_etch_key, key))
    key = 'where plain'
    assert_equal(key, @etch.send(:symbolize_etch_key, key))
  end
  test 'symbolize_etch_keys' do
    assert_equal({a: {b: 1}}, @etch.send(:symbolize_etch_keys, {'a' => {'b' => 1}}))
    assert_equal({a: {b: 1}}, @etch.send(:symbolize_etch_keys, {'a' => {:b => 1}}))
    assert_equal({a: {b: 1}}, @etch.send(:symbolize_etch_keys, {:a => {'b' => 1}}))
    assert_equal({a: {b: 1}}, @etch.send(:symbolize_etch_keys, {:a => {:b => 1}}))
    assert_equal({a: [{b: 1}]}, @etch.send(:symbolize_etch_keys, {'a' => [{'b' => 1}]}))
  end
  test 'load_nodes none' do
    assert_equal([{}, '<none>'], @etch.send(:load_nodes))
  end
  test 'load_nodes yaml empty' do
    File.open("#{@configdir}/nodes.yml", 'w') do |file|
    end
    assert_equal([{}, 'nodes.yml'], @etch.send(:load_nodes))
  end
  test 'load_nodes yaml' do
    data = {'server1.example.com' => ['group1', 'group2'], 'server2.example.com' => ['group3']}
    File.open("#{@configdir}/nodes.yml", 'w') do |file|
      file.write data.to_yaml
    end
    assert_equal([data, 'nodes.yml'], @etch.send(:load_nodes))
  end
  test 'load_nodes xml empty' do
    File.open("#{@configdir}/nodes.xml", 'w') do |file|
    end
    assert_equal([{}, 'nodes.xml'], @etch.send(:load_nodes))
  end
  test 'load_nodes xml' do
    data = {'server1.example.com' => ['group1', 'group2'], 'server2.example.com' => ['group3']}
    File.open("#{@configdir}/nodes.xml", 'w') do |file|
      file.write <<-EOS
      <nodes>
        <node name="server1.example.com">
          <group>group1</group>
          <group>group2</group>
        </node>
        <node name="server2.example.com">
          <group>group3</group>
        </node>
      </nodes>
      EOS
    end
    assert_equal([data, 'nodes.xml'], @etch.send(:load_nodes))
  end
  test 'load_nodes both' do
    data = {'server1.example.com' => ['group1', 'group2'], 'server2.example.com' => ['group3']}
    File.open("#{@configdir}/nodes.yml", 'w') do |file|
      file.write data.to_yaml
    end
    File.open("#{@configdir}/nodes.xml", 'w') do |file|
      file.write <<-EOS
      <nodes>
        <node name="server3.example.com">
          <group>group4</group>
        </node>
      </nodes>
      EOS
    end
    assert_equal([data, 'nodes.yml'], @etch.send(:load_nodes))
  end
  test 'load_nodegroups none' do
    assert_equal({}, @etch.send(:load_nodegroups))
  end
  test 'load_nodegroups yaml empty' do
    File.open("#{@configdir}/nodegroups.yml", 'w') do |file|
    end
    assert_equal({}, @etch.send(:load_nodegroups))
  end
  test 'load_nodegroups yaml' do
    data = {'pgroup1' => ['cgroup1', 'cgroup2'], 'pgroup2' => ['cgroup3']}
    File.open("#{@configdir}/nodegroups.yml", 'w') do |file|
      file.write data.to_yaml
    end
    assert_equal(data, @etch.send(:load_nodegroups))
  end
  test 'load_nodegroups xml empty' do
    File.open("#{@configdir}/nodegroups.xml", 'w') do |file|
    end
    assert_equal({}, @etch.send(:load_nodegroups))
  end
  test 'load_nodegroups xml' do
    data = {'pgroup1' => ['cgroup1', 'cgroup2'], 'pgroup2' => ['cgroup3']}
    File.open("#{@configdir}/nodegroups.xml", 'w') do |file|
      file.write <<-EOS
      <nodegroups>
        <nodegroup name="pgroup1">
          <child>cgroup1</child>
          <child>cgroup2</child>
        </nodegroup>
        <nodegroup name="pgroup2">
          <child>cgroup3</child>
        </nodegroup>
      </nodegroups>
      EOS
    end
    assert_equal(data, @etch.send(:load_nodegroups))
  end
  test 'load_nodegroups both' do
    data = {'server1.example.com' => ['group1', 'group2'], 'server2.example.com' => ['group3']}
    File.open("#{@configdir}/nodegroups.yml", 'w') do |file|
      file.write data.to_yaml
    end
    File.open("#{@configdir}/nodegroups.xml", 'w') do |file|
      file.write <<-EOS
      <nodegroups>
        <nodegroup name="pgroup3">
          <child>cgroup4</child>
        </nodegroup>
      </nodegroups>
      EOS
    end
    assert_equal(data, @etch.send(:load_nodegroups))
  end
  test 'get_parent_nodegroups' do
    nodegroups = {
      'grandparent' => ['parent', 'other'],
      'parent' => ['child', 'other'],
      'child' => ['other'],
    }
    @etch.instance_variable_set(:@group_hierarchy, nodegroups)
    assert_equal(Set.new(['grandparent', 'parent']), @etch.send(:get_parent_nodegroups, 'child'))
    assert_equal(Set.new(['grandparent']), @etch.send(:get_parent_nodegroups, 'parent'))
    assert_equal(Set.new, @etch.send(:get_parent_nodegroups, 'grandparent'))
    assert_equal(Set.new, @etch.send(:get_parent_nodegroups, 'random'))
  end

  test 'generate_file' do
    # FIXME: need to test
  end

  test 'load_config yaml' do
    FileUtils.mkdir_p("#{@configdir}/source/test")
    data = {a: [{:b => 'c'}, 'd']}
    File.open("#{@configdir}/source/test/config.yml", 'w') do |file|
      file.write data.to_yaml
    end
    assert_equal(data, @etch.send(:load_config, 'test'))
  end
  test 'load_config xml' do
    FileUtils.mkdir_p("#{@configdir}/source/test")
    File.open("#{@configdir}/source/test/config.xml", 'w') do |file|
      file.write '<config><file><source><plain>plainfile</plain></source></file></config>'
    end
    assert_equal({file: {plain: ['plainfile']}}, @etch.send(:load_config, 'test'))
  end
  test 'load_config empty' do
    FileUtils.mkdir_p("#{@configdir}/source/test")
    assert_raise(RuntimeError) {@etch.send(:load_config, 'test')}
  end
  test 'load_command yaml' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {guard: 'true', command: ['ls', 'grep']}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    assert_equal(data, @etch.send(:load_command, 'test'))
  end

  test 'generate_commands already generated' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {guard: ['true', 'false'], command: ['ls', 'grep']}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {'test' => true})
    # Note that I've set these two intentionally wrong to ensure that the commands
    # are not in fact generated again
    @etch.instance_variable_set(:@generation_status, {'test' => :unknown})
    @etch.instance_variable_set(:@commands, {'test' => nil})

    assert_equal(:unknown, @etch.send(:generate_commands, 'test', nil))
    assert_equal({}, @etch.instance_variable_get(:@filestack))
    assert_equal({'test' => true}, @etch.instance_variable_get(:@already_generated))
    assert_equal({'test' => :unknown}, @etch.instance_variable_get(:@generation_status))
    assert_equal({'test' => nil}, @etch.instance_variable_get(:@commands))
  end
  test 'generate_commands circular dependency' do
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {'test' => true})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_raise(RuntimeError) {@etch.send(:generate_commands, 'test', nil)}
  end
  test 'generate_commands depend' do
    data = {depend: ['test2'], steps: [{step: {guard: ['true'], command: ['ls']}}]}
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    data2 = {steps: [{step: {guard: ['false'], command: ['grep']}}]}
    FileUtils.mkdir_p("#{@configdir}/commands/test2")
    File.open("#{@configdir}/commands/test2/commands.yml", 'w') do |file|
      file.write data2.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_equal(:success, @etch.send(:generate_commands, 'test', nil))
    assert_equal({}, @etch.instance_variable_get(:@filestack))
    assert_equal({'test' => true, 'test2' => true}, @etch.instance_variable_get(:@already_generated))
    assert_equal({'test' => :success, 'test2' => :success}, @etch.instance_variable_get(:@generation_status))
    assert_equal({'test' => data, 'test2' => data2}, @etch.instance_variable_get(:@commands))
  end
  test 'generate_commands dependfile' do
    testname = 'generate_commands dependfile'
    data = {dependfile: ['/testfile'], steps: [{step: {guard: ['true'], command: ['ls']}}]}
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    filedata = {file: {plain: 'source'}}
    FileUtils.mkdir_p("#{@configdir}/source/testfile")
    File.open("#{@configdir}/source/testfile/config.yml", 'w') do |file|
      file.write filedata.to_yaml
    end
    sourcecontents = "Test #{testname}\n"
    File.open("#{@configdir}/source/testfile/source", 'w') do |file|
      file.write sourcecontents
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})
    @etch.instance_variable_set(:@configs, {})
    FileUtils.cp("#{File.dirname(__FILE__)}/../../../test/testrepo/defaults.yml", @configdir)
    @etch.instance_variable_set(:@defaults, @etch.send(:load_defaults))

    request = {files: {'/testfile' => {orig: ''}}}
    assert_equal(:success, @etch.send(:generate_commands, 'test', request))
    assert_equal({}, @etch.instance_variable_get(:@filestack))
    assert_equal({'test' => true, '/testfile' => true}, @etch.instance_variable_get(:@already_generated))
    assert_equal({'test' => :success, '/testfile' => :success}, @etch.instance_variable_get(:@generation_status))
    assert_equal({'test' => data}, @etch.instance_variable_get(:@commands))
    expectfiledata = {'/testfile' => {file: {contents: Base64.encode64(sourcecontents), owner: 0, group: 0, perms: 444}}}
    assert_equal(expectfiledata, @etch.instance_variable_get(:@configs))
  end
  test 'generate_commands empty commands' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_equal(:unknown, @etch.send(:generate_commands, 'test', nil))
    assert_equal({}, @etch.instance_variable_get(:@filestack))
    assert_equal({'test' => true}, @etch.instance_variable_get(:@already_generated))
    assert_equal({'test' => :unknown}, @etch.instance_variable_get(:@generation_status))
    assert_equal({}, @etch.instance_variable_get(:@commands))
  end
  test 'generate_commands empty step' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_equal(:unknown, @etch.send(:generate_commands, 'test', nil))
    assert_equal({}, @etch.instance_variable_get(:@filestack))
    assert_equal({'test' => true}, @etch.instance_variable_get(:@already_generated))
    assert_equal({'test' => :unknown}, @etch.instance_variable_get(:@generation_status))
    assert_equal({}, @etch.instance_variable_get(:@commands))
  end
  test 'generate_commands empty array step' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {guard: [], command: []}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_equal(:unknown, @etch.send(:generate_commands, 'test', nil))
    assert_equal({}, @etch.instance_variable_get(:@filestack))
    assert_equal({'test' => true}, @etch.instance_variable_get(:@already_generated))
    assert_equal({'test' => :unknown}, @etch.instance_variable_get(:@generation_status))
    assert_equal({}, @etch.instance_variable_get(:@commands))
  end
  test 'generate_commands no guard' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {command: ['ls']}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_raise(RuntimeError) {@etch.send(:generate_commands, 'test', nil)}
  end
  test 'generate_commands no guard array' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {guard: [], command: ['ls']}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_raise(RuntimeError) {@etch.send(:generate_commands, 'test', nil)}
  end
  test 'generate_commands no command' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {guard: ['true']}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_raise(RuntimeError) {@etch.send(:generate_commands, 'test', nil)}
  end
  test 'generate_commands no command array' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {guard: ['true'], command: []}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_raise(RuntimeError) {@etch.send(:generate_commands, 'test', nil)}
  end
  test 'generate_commands scalar data' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {guard: 'true', command: 'ls'}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_equal(:success, @etch.send(:generate_commands, 'test', nil))
    assert_equal({}, @etch.instance_variable_get(:@filestack))
    assert_equal({'test' => true}, @etch.instance_variable_get(:@already_generated))
    assert_equal({'test' => :success}, @etch.instance_variable_get(:@generation_status))
    data[:steps].first[:step][:guard] = [data[:steps].first[:step][:guard]]
    data[:steps].first[:step][:command] = [data[:steps].first[:step][:command]]
    assert_equal({'test' => data}, @etch.instance_variable_get(:@commands))
  end
  test 'generate_commands array data' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    data = {steps: [{step: {guard: ['true', 'false'], command: ['ls', 'grep']}}]}
    File.open("#{@configdir}/commands/test/commands.yml", 'w') do |file|
      file.write data.to_yaml
    end
    # These are normally initialized by the generate method
    @etch.instance_variable_set(:@filestack, {})
    @etch.instance_variable_set(:@already_generated, {})
    @etch.instance_variable_set(:@generation_status, {})
    @etch.instance_variable_set(:@commands, {})

    assert_equal(:success, @etch.send(:generate_commands, 'test', nil))
    assert_equal({}, @etch.instance_variable_get(:@filestack))
    assert_equal({'test' => true}, @etch.instance_variable_get(:@already_generated))
    assert_equal({'test' => :success}, @etch.instance_variable_get(:@generation_status))
    assert_equal({'test' => data}, @etch.instance_variable_get(:@commands))
  end

  test 'load_command xml' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    File.open("#{@configdir}/commands/test/commands.xml", 'w') do |file|
      file.write '<commands><step><guard><exec>true</exec><exec>false</exec></guard><command><exec>ls</exec><exec>grep</exec></command></step></commands>'
    end
    assert_equal({steps: [{step: {guard: ['true', 'false'], command: ['ls', 'grep']}}]}, @etch.send(:load_command, 'test'))
  end
  test 'load_command empty' do
    FileUtils.mkdir_p("#{@configdir}/commands/test")
    assert_raise(RuntimeError) {@etch.send(:load_command, 'test')}
  end
  test 'filter_config_completely no keepers' do
    testdata = {:depend => true, :post => false, :bogon1 => 1, :bogin2 => 2}
    @etch.send(:filter_config_completely!, testdata)
    assert_equal({}, testdata)
  end
  test 'filter_config_completely with keepers' do
    testdata = {:depend => true, :post => false, :bogon1 => 1, :bogin2 => 2}
    @etch.send(:filter_config_completely!, testdata, [:depend, :bogon1])
    assert_equal({:depend => true, :bogon1 => 1}, testdata)
  end
  test 'filter_config no keepers' do
    testdata = {:depend => true, :post => false, :bogon1 => 1, :bogin2 => 2}
    @etch.send(:filter_config!, testdata)
    assert_equal({:depend => true, :post => false}, testdata)
  end
  test 'filter_config with keepers' do
    testdata = {:depend => true, :post => false, :bogon1 => 1, :bogin2 => 2}
    @etch.send(:filter_config!, testdata, [:bogon1])
    assert_equal({:depend => true, :post => false, :bogon1 => 1}, testdata)
  end
  test 'yamlfilter' do
    @etch.instance_variable_set(:@facts, {'operatingsystem' => 'RedHat'})
    testhash = {
      :a => 1,
      :b => [true],
      :plain => {'where operatingsystem==SunOS' => 'foo'},
      :script => {'where operatingsystem==RedHat' => 'foo.script'},
      :nested => {
        :plain => {'where operatingsystem==SunOS' => 'foo'},
        :script => {'where operatingsystem==RedHat' => 'foo.script'},
      },
      :array => [
        {'where operatingsystem==RedHat' => 'redhat.script'},
        {'where operatingsystem==SunOS' => 'sunos.script'},
        'all.script',
        {'where operatingsystem==FreeBSD' => 'freebsd.script'},
      ],
      :nestedarray => [
        :a,
        {
          :plain => {'where operatingsystem==SunOS' => 'foo'},
          :script => {'where operatingsystem==RedHat' => 'foo.script'}
        },
        {:plain => {'where operatingsystem==SunOS' => 'foo'}},
        {:script => {'where operatingsystem==RedHat' => 'bar.script'}},
        {'where foo' => false, 'where bar' => true},
      ],
      :other => {'where foo' => false, 'where bar' => true},
    }
    filterhash = Marshal.load(Marshal.dump testhash)
    filterhash.delete(:plain)
    filterhash[:script] = filterhash[:script].values.first
    filterhash[:nested].delete(:plain)
    filterhash[:nested][:script] = filterhash[:nested][:script].values.first
    filterhash[:array][0] = filterhash[:array][0].values.first
    filterhash[:array].delete_at(1)
    filterhash[:array].delete_at(2) # FreeBSD entry will be at 2 after previous delete
    filterhash[:nestedarray][1].delete(:plain)
    filterhash[:nestedarray][1][:script] = filterhash[:nestedarray][1][:script].values.first
    filterhash[:nestedarray][2].clear
    filterhash[:nestedarray][3][:script] = filterhash[:nestedarray][3][:script].values.first
    @etch.send(:yamlfilter!, testhash)
    assert_equal(filterhash, testhash)
  end
  test 'eval_yaml_condition' do
    @etch.instance_variable_set(:@facts, {'operatingsystem' => 'RedHat', 'operatingsystemrelease' => '6.5'})
    @etch.instance_variable_set(:@groups, ['one', 'two'])

    assert @etch.send(:eval_yaml_condition, 'group == one')
    assert @etch.send(:eval_yaml_condition, 'group ==one')
    assert @etch.send(:eval_yaml_condition, 'group==one')
    refute @etch.send(:eval_yaml_condition, 'group ==three')
    refute @etch.send(:eval_yaml_condition, 'group==three')

    refute @etch.send(:eval_yaml_condition, 'group != one')
    assert @etch.send(:eval_yaml_condition, 'group != three')

    assert @etch.send(:eval_yaml_condition, 'operatingsystem =~ Red')
    assert @etch.send(:eval_yaml_condition, 'operatingsystem =~ \ARed')
    refute @etch.send(:eval_yaml_condition, 'operatingsystem =~ \AHat')
    refute @etch.send(:eval_yaml_condition, 'operatingsystem !~ Red')
    assert @etch.send(:eval_yaml_condition, 'operatingsystem !~ \AHat')
    refute @etch.send(:eval_yaml_condition, 'operatingsystem !~ Hat')

    assert @etch.send(:eval_yaml_condition, 'operatingsystemrelease == 6.5')
    assert @etch.send(:eval_yaml_condition, 'operatingsystemrelease != 6.4')
    assert @etch.send(:eval_yaml_condition, 'operatingsystemrelease >= 6.5')
    assert @etch.send(:eval_yaml_condition, 'operatingsystemrelease > 6.1')
    assert @etch.send(:eval_yaml_condition, 'operatingsystemrelease > 6.1.1')
    refute @etch.send(:eval_yaml_condition, 'operatingsystemrelease > 6.5')
    assert @etch.send(:eval_yaml_condition, 'operatingsystemrelease <= 6.5')
    assert @etch.send(:eval_yaml_condition, 'operatingsystemrelease < 6.9')
    refute @etch.send(:eval_yaml_condition, 'operatingsystemrelease < 6.2')

    assert @etch.send(:eval_yaml_condition, 'operatingsystem =~ Red and group == one')
    assert @etch.send(:eval_yaml_condition, 'operatingsystem =~ Red or group == three')
    refute @etch.send(:eval_yaml_condition, 'operatingsystem =~ Red and group == three')
    assert @etch.send(:eval_yaml_condition, 'operatingsystem =~ Red and group == one or group == three')
    refute @etch.send(:eval_yaml_condition, 'operatingsystem =~ Red and group == three or group == one')
  end
  test 'xmlfilter' do
    @etch.instance_variable_set(:@facts, {'operatingsystem' => 'RedHat'})
    testconfig = <<-EOS
    <config>
      <file>
        <source>
          <plain operatingsystem="RedHat">redhat</plain>
          <plain operatingsystem="SunOS">sunos</plain>
        </source>
      </file>
      <link operatingsystem="HPUX">
        <dest>linkdest</dest>
      </link>
    </config>
    EOS
    filterconfig = <<-EOS
    <config>
      <file>
        <source>
          <plain>redhat</plain>
        </source>
      </file>
    </config>
    EOS
    testdoc = Etch.xmlloadstr(testconfig)
    @etch.send(:xmlfilter!, Etch.xmlroot(testdoc))
    filterdoc = Etch.xmlloadstr(filterconfig)
    # assert_equal(filterdoc, testdoc)
    assert_equal(filterdoc.to_s.gsub(/\s/, ''), testdoc.to_s.gsub(/\s/, ''))
  end
  test 'comparables' do
    @etch.instance_variable_set(:@facts, {'operatingsystem' => 'RedHat'})
    groups = ['one', 'two']
    @etch.instance_variable_set(:@groups, groups)
    assert_equal(groups, @etch.send(:comparables, 'group'))
    assert_equal(['RedHat'], @etch.send(:comparables, 'operatingsystem'))
  end
  test 'check_attribute' do
    @etch.instance_variable_set(:@facts, {'operatingsystem' => 'RedHat', 'operatingsystemrelease' => '6.5'})
    @etch.instance_variable_set(:@groups, ['one', 'two'])

    assert @etch.send(:check_attribute, 'group', 'one')
    refute @etch.send(:check_attribute, 'group', '!one')
    refute @etch.send(:check_attribute, 'group', 'three')
    assert @etch.send(:check_attribute, 'group', '!three')

    assert @etch.send(:check_attribute, 'operatingsystem', '/Red/')
    assert @etch.send(:check_attribute, 'operatingsystem', '/\ARed/')
    refute @etch.send(:check_attribute, 'operatingsystem', '/\AHat/')
    refute @etch.send(:check_attribute, 'operatingsystem', '!/Red/')
    assert @etch.send(:check_attribute, 'operatingsystem', '!/\AHat/')
    refute @etch.send(:check_attribute, 'operatingsystem', '!/Hat/')

    assert @etch.send(:check_attribute, 'operatingsystemrelease', '>=6.5')
    refute @etch.send(:check_attribute, 'operatingsystemrelease', '!>=6.5')
    assert @etch.send(:check_attribute, 'operatingsystemrelease', '>6.1')
    assert @etch.send(:check_attribute, 'operatingsystemrelease', '>6.1.1')
    refute @etch.send(:check_attribute, 'operatingsystemrelease', '>6.5')
    assert @etch.send(:check_attribute, 'operatingsystemrelease', '<=6.5')
    assert @etch.send(:check_attribute, 'operatingsystemrelease', '<6.9')
    refute @etch.send(:check_attribute, 'operatingsystemrelease', '<6.2')
    assert @etch.send(:check_attribute, 'operatingsystemrelease', '!<6.2')

    assert @etch.send(:check_attribute, 'operatingsystem', 'RedHat')
    refute @etch.send(:check_attribute, 'operatingsystem', '!RedHat')
  end
  test 'config_xml_to_hash' do
    testconfig = <<-EOS
    <config>
      <revert/>
      <depend>depone</depend>
      <depend>deptwo</depend>
      <dependcommand>depcmd</dependcommand>
      <server_setup><exec>ssetup</exec></server_setup>
      <setup><exec>setupone</exec><exec>setuptwo</exec></setup>
      <pre><exec>prething</exec></pre>
      <file>
        <owner>nobody</owner>
        <perms>755</perms>
        <warning_on_second_line/>
        <source>
          <plain>plainfile</plain>
          <plain>plainfile</plain>
          <plain>plainfile2</plain>
        </source>
      </file>
      <link>
        <group>someone</group>
        <perms>600</perms>
        <overwrite_directory/>
        <script>linkscript</script>
      </link>
      <directory>
        <owner>nouser</owner>
        <perms>750</perms>
        <create/>
      </directory>
      <delete>
        <overwrite_directory/>
        <proceed/>
      </delete>
      <test_before_post><exec>tbp</exec></test_before_post>
      <post>
        <exec>postone</exec>
        <exec>posttwo</exec>
        <exec_once>postonce</exec_once>
        <exec_once_per_run>postonceperone</exec_once_per_run>
        <exec_once_per_run>postoncepertwo</exec_once_per_run>
      </post>
      <test><exec>testone</exec><exec>testtwo</exec></test>
    </config>
    EOS
    expected = {
      revert: true,
      depend: ['depone', 'deptwo'],
      dependcommand: ['depcmd'],
      server_setup: ['ssetup'],
      setup: ['setupone', 'setuptwo'],
      pre: ['prething'],
      file: {
        owner: 'nobody',
        perms: '755',
        warning_on_second_line: true,
        plain: ['plainfile', 'plainfile', 'plainfile2'],
      },
      link: {
        group: 'someone',
        perms: '600',
        overwrite_directory: true,
        script: ['linkscript'],
      },
      directory: {
        owner: 'nouser',
        perms: '750',
        create: true,
      },
      delete: {
        overwrite_directory: true,
        proceed: true,
      },
      test_before_post: ['tbp'],
      post: ['postone', 'posttwo'],
      post_once: ['postonce'],
      post_once_per_run: ['postonceperone', 'postoncepertwo'],
      test: ['testone', 'testtwo'],
    }
    testdoc = Etch.xmlloadstr(testconfig)
    assert_equal(expected, Etch.config_xml_to_hash(testdoc))
  end
  test 'config_hash_to_xml' do
    testhash = {
      revert: true,
      depend: ['depone', 'deptwo'],
      dependcommand: ['depcmd'],
      server_setup: ['ssetup'],
      setup: ['setupone', 'setuptwo'],
      pre: ['prething'],
      file: {
        owner: 'nobody',
        perms: '755',
        contents: 'filecontents',
      },
      link: {
        group: 'someone',
        perms: '600',
        overwrite_directory: true,
        dest: 'linkdest',
      },
      directory: {
        owner: 'nouser',
        perms: '750',
        create: true,
      },
      delete: {
        overwrite_directory: true,
        proceed: true,
      },
      test_before_post: ['tbp'],
      post: ['postone', 'posttwo'],
      post_once: ['postonce'],
      post_once_per_run: ['postonceperone', 'postoncepertwo'],
      test: ['testone', 'testtwo'],
    }
    expected = <<-EOS
    <config filename="testfile">
      <revert/>
      <depend>depone</depend>
      <depend>deptwo</depend>
      <dependcommand>depcmd</dependcommand>
      <setup><exec>setupone</exec><exec>setuptwo</exec></setup>
      <pre><exec>prething</exec></pre>
      <file>
        <owner>nobody</owner>
        <perms>755</perms>
        <contents>filecontents</contents>
      </file>
      <link>
        <group>someone</group>
        <perms>600</perms>
        <overwrite_directory/>
        <dest>linkdest</dest>
      </link>
      <directory>
        <owner>nouser</owner>
        <perms>750</perms>
        <create/>
      </directory>
      <delete>
        <overwrite_directory/>
        <proceed/>
      </delete>
      <test_before_post><exec>tbp</exec></test_before_post>
      <post>
        <exec_once>postonce</exec_once>
        <exec_once_per_run>postonceperone</exec_once_per_run>
        <exec_once_per_run>postoncepertwo</exec_once_per_run>
        <exec>postone</exec>
        <exec>posttwo</exec>
      </post>
      <test><exec>testone</exec><exec>testtwo</exec></test>
    </config>
    EOS
    expectdoc = Etch.xmlloadstr(expected)
    assert_equal(expectdoc.to_s.gsub(/\s/, ''), Etch.config_hash_to_xml(testhash, 'testfile').to_s.gsub(/\s/, ''))
  end
  test 'command_xml_to_hash' do
    testcmd = <<-EOS
    <commands>
      <depend>depone</depend>
      <depend>deptwo</depend>
      <dependfile>depfile</dependfile>
      <step>
        <guard>
          <exec>s1guard1</exec>
          <exec>s1guard2</exec>
        </guard>
        <command>
          <exec>s1command1</exec>
        </command>
      </step>
      <step>
        <guard>
          <exec>s2guard1</exec>
        </guard>
        <command>
          <exec>s2command1</exec>
          <exec>s2command2</exec>
        </command>
      </step>
    </commands>
    EOS
    expected = {
      depend: ['depone', 'deptwo'],
      dependfile: ['depfile'],
      steps: [
        {
          step: {
            guard: ['s1guard1', 's1guard2'],
            command: ['s1command1'],
          },
        },
        {
          step: {
            guard: ['s2guard1'],
            command: ['s2command1', 's2command2'],
          },
        },
      ],
    }
    testdoc = Etch.xmlloadstr(testcmd)
    assert_equal(expected, Etch.command_xml_to_hash(testdoc))
  end
  test 'command_hash_to_xml' do
    testhash = {
      depend: ['depone', 'deptwo'],
      dependfile: ['depfile'],
      steps: [
        {
          step: {
            guard: ['s1guard1', 's1guard2'],
            command: ['s1command1'],
          },
        },
        {
          step: {
            guard: ['s2guard1'],
            command: ['s2command1', 's2command2'],
          },
        },
      ],
    }
    expected = <<-EOS
    <commands commandname="testcommand">
      <depend>depone</depend>
      <depend>deptwo</depend>
      <dependfile>depfile</dependfile>
      <step>
        <guard>
          <exec>s1guard1</exec>
          <exec>s1guard2</exec>
        </guard>
        <command>
          <exec>s1command1</exec>
        </command>
      </step>
      <step>
        <guard>
          <exec>s2guard1</exec>
        </guard>
        <command>
          <exec>s2command1</exec>
          <exec>s2command2</exec>
        </command>
      </step>
    </commands>
    EOS
    expectdoc = Etch.xmlloadstr(expected)
    assert_equal(expectdoc.to_s.gsub(/\s/, ''), Etch.command_hash_to_xml(testhash, 'testcommand').to_s.gsub(/\s/, ''))
  end
  test 'check_for_inconsistency' do
    refute @etch.send(:check_for_inconsistency, [])
    refute @etch.send(:check_for_inconsistency, [1])
    refute @etch.send(:check_for_inconsistency, [1,1,1])
    assert @etch.send(:check_for_inconsistency, [1,2,1])
    assert @etch.send(:check_for_inconsistency, [1,1,2])
    assert @etch.send(:check_for_inconsistency, [1,1,nil])
  end
end
