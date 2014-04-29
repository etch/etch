require 'test_helper'

class FactTest < ActiveSupport::TestCase
  # FIXME: need to test
  # attr_accessible :client, :client_id, :key, :value

  test 'belongs to client' do
    f = Fact.new(client_id: clients(:one).id)
    f.client = clients(:one)
  end

  test 'client is required' do
    f = Fact.new
    refute f.valid?
    assert f.errors[:client].any?
    f.client = clients(:one)
    f.valid?
    refute f.errors[:client].any?
  end
  test 'key is required' do
    f = Fact.new
    refute f.valid?
    assert f.errors[:key].any?
    f.key = 'test'
    f.valid?
    refute f.errors[:key].any?
  end

  test 'optional value' do
    f = Fact.new
    f.valid?
    refute f.errors[:value].any?
    f.value = 'test'
    f.valid?
    refute f.errors[:value].any?
  end
end
