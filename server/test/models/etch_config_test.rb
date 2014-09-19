require 'test_helper'

class EtchConfigTest < ActiveSupport::TestCase
  test 'belongs to client' do
    c = EtchConfig.new(client_id: clients(:one).id)
    c.client = clients(:one)
  end
  
  test 'client is required' do
    c = EtchConfig.new
    refute c.valid?
    assert c.errors[:client].any?
    c.client = clients(:one)
    c.valid?
    refute c.errors[:client].any?
  end
  test 'file is required' do
    c = EtchConfig.new
    refute c.valid?
    assert c.errors[:file].any?
    c.file = 'test'
    c.valid?
    refute c.errors[:file].any?
  end
  test 'config is required' do
    c = EtchConfig.new
    refute c.valid?
    assert c.errors[:config].any?
    c.config = 'test'
    c.valid?
    refute c.errors[:config].any?
  end
  
  test 'config setter compresses data' do
    c = etch_configs(:one)
    data = 'test data'
    c.config = data
    assert_equal Zlib::Deflate.deflate(data), c.read_attribute(:config)
  end
  test 'config getter uncompresses data' do
    c = etch_configs(:one)
    data = 'test data'
    c.send(:write_attribute, :config, Zlib::Deflate.deflate(data))
    assert_equal data, c.config
  end
  test 'config getter handles uncompressed data' do
    c = etch_configs(:one)
    data = 'test data'
    c.send(:write_attribute, :config, data)
    assert_equal data, c.config
  end
end
