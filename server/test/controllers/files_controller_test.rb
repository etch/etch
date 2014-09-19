require 'test_helper'

class FilesControllerTest < ActionController::TestCase
  # Older clients don't request a specific content type and expect to get XML
  # It is unclear how to simulate a client sending an Accept header of
  # '*/*' (which is what older clients do)
  # test 'xml is default format' do
  #   fakeserver = mock('etch_server')
  #   Etch::Server.expects(:new).returns(fakeserver)
  #   fakeserver.expects(:generate).returns('<files></files>')
  #   post :create, facts: {fqdn: 'test.example.com'}, format: :any
  #   assert_equal 'application/xml', response.content_type
  # end
  # FIXME: need to test the handling of params[:files] and params[:commands]
  test 'xml format' do
    fakeserver = mock('etch_server')
    Etch::Server.expects(:new).returns(fakeserver)
    fakeserver.expects(:generate).returns('<files></files>')
    post :create, facts: {fqdn: 'test.example.com'}, format: :xml
    assert_equal 'application/xml', response.content_type
  end
  test 'yaml format' do
    fakeserver = mock('etch_server')
    Etch::Server.expects(:new).returns(fakeserver)
    fakeserver.expects(:generate).returns({}.to_yaml)
    post :create, facts: {fqdn: 'test.example.com'}, format: :yaml
    assert_equal 'application/x-yaml', response.content_type
  end
  test 'json format' do
    fakeserver = mock('etch_server')
    Etch::Server.expects(:new).returns(fakeserver)
    fakeserver.expects(:generate).returns({}.to_json)
    post :create, facts: {fqdn: 'test.example.com'}, format: :json
    assert_equal 'application/json', response.content_type
  end
end
