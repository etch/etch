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
        </file>
      </config>
      EOF
    end
    defaults = @etch.send :load_defaults
    assert_equal(1, defaults[:file][:owner])
    assert_equal('warning.txt', defaults[:file][:warning_file])
    assert_equal({}, defaults[:link])
  end
  test 'symbolize keys' do
    assert_equal({a: {b: 1}}, @etch.send(:symbolize_keys, {'a' => {'b' => 1}}))
    assert_equal({a: {b: 1}}, @etch.send(:symbolize_keys, {'a' => {:b => 1}}))
    assert_equal({a: {b: 1}}, @etch.send(:symbolize_keys, {:a => {'b' => 1}}))
    assert_equal({a: {b: 1}}, @etch.send(:symbolize_keys, {:a => {:b => 1}}))
  end
end
