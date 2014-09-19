require 'test_helper'

class ClientTest < ActiveSupport::TestCase
  test 'has many facts' do
    assert_kind_of Fact, clients(:one).facts.first
  end
  test 'facts are dependent destroy' do
    fact = clients(:one).facts.first
    clients(:one).destroy
    refute Fact.exists?(fact.id)
  end
  test 'has many originals' do
    assert_kind_of Original, clients(:one).originals.first
  end
  test 'originals are dependent destroy' do
    orig = clients(:one).originals.first
    clients(:one).destroy
    refute Original.exists?(orig.id)
  end
  test 'has many configs' do
    assert_kind_of EtchConfig, clients(:one).etch_configs.first
  end
  test 'configs are dependent destroy' do
    config = clients(:one).etch_configs.first
    clients(:one).destroy
    refute EtchConfig.exists?(config.id)
  end
  test 'has many results' do
    assert_kind_of Result, clients(:one).results.first
  end
  test 'results are dependent destroy' do
    result = clients(:one).results.first
    clients(:one).destroy
    refute Result.exists?(result.id)
  end

  test 'name is required' do
    c = Client.new
    refute c.valid?
    assert c.errors[:name].any?
    c.name = 'name'
    c.valid?
    refute c.errors[:name].any?
  end
  test 'name must be unique' do
    c = Client.new
    c.name = clients(:one).name
    refute c.valid?
    assert c.errors[:name].any?
    c.name = 'some other name'
    c.valid?
    refute c.errors[:name].any?
  end
  test 'status must be an integer' do
    c = Client.new
    c.status = 1.1
    refute c.valid?
    assert c.errors[:status].any?
    c.status = 1
    c.valid?
    refute c.errors[:status].any?
  end
  test 'status may be nil' do
    c = Client.new
    c.valid?
    refute c.errors[:status].any?
  end
  test 'optional message' do
    c = Client.new
    c.valid?
    refute c.errors[:message].any?
    c.message = 'test'
    c.valid?
    refute c.errors[:message].any?
  end

  test 'healthy scope' do
    assert_equal [clients(:healthy_recent)], Client.healthy.to_a
  end
  test 'broken scope' do
    assert_equal [clients(:broken_recent)], Client.broken.to_a
  end
  test 'disabled scope' do
    assert_equal [clients(:disabled_recent)], Client.disabled.to_a
  end
  test 'stale scope' do
    expected = [clients(:healthy_old), clients(:broken_old), clients(:disabled_old)]
    assert_equal [], expected - Client.stale.to_a
    assert_equal [], Client.stale.to_a - expected
  end
end
