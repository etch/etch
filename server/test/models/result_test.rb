require 'test_helper'

class ResultTest < ActiveSupport::TestCase
  test 'belongs to client' do
    r = Result.new(client_id: clients(:one).id)
    r.client = clients(:one)
  end

  test 'client is required' do
    r = Result.new
    refute r.valid?
    assert r.errors[:client].any?
    r.client = clients(:one)
    r.valid?
    refute r.errors[:client].any?
  end
  test 'file is required' do
    r = Result.new
    refute r.valid?
    assert r.errors[:file].any?
    r.file = 'test'
    r.valid?
    refute r.errors[:file].any?
  end
  test 'message is required' do
    r = Result.new
    refute r.valid?
    assert r.errors[:message].any?
    r.message = 'test'
    r.valid?
    refute r.errors[:message].any?
  end
  test 'success is required and boolean' do
    r = Result.new
    refute r.valid?
    assert r.errors[:success].any?
    r.success = 'test'
    r.valid?
    refute r.errors[:success].any?
    assert_equal false, r.success
    r.success = true
    r.valid?
    refute r.errors[:success].any?
    r.success = false
    r.valid?
    refute r.errors[:success].any?
  end
end
