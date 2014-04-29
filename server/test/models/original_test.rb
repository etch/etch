require 'test_helper'

class OriginalTest < ActiveSupport::TestCase
  # FIXME: need to test
  # attr_accessible :client, :client_id, :file, :sum

  test 'belongs to client' do
    o = Original.new(client_id: clients(:one).id)
    o.client = clients(:one)
  end

  test 'client is required' do
    o = Original.new
    refute o.valid?
    assert o.errors[:client].any?
    o.client = clients(:one)
    o.valid?
    refute o.errors[:client].any?
  end
  test 'file is required' do
    o = Original.new
    refute o.valid?
    assert o.errors[:file].any?
    o.file = 'test'
    o.valid?
    refute o.errors[:file].any?
  end
  test 'sum is required' do
    o = Original.new
    refute o.valid?
    assert o.errors[:sum].any?
    o.sum = 'test'
    o.valid?
    refute o.errors[:sum].any?
  end
end
