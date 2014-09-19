require 'test_helper'
require 'rexml/document'

class ClientsControllerTest < ActionController::TestCase
  test 'index default' do
    get :index
    assert_response :success
    assert_not_nil assigns(:q)
    assert_not_nil assigns(:clients)
    assert_equal 8, assigns(:clients).length
  end
  test 'index healthy' do
    get :index, {'health' => 'healthy'}
    assert_response :success
    assert_equal 1, assigns(:clients).length
  end
  test 'index broken' do
    get :index, {'health' => 'broken'}
    assert_response :success
    assert_equal 1, assigns(:clients).length
  end
  test 'index disabled' do
    get :index, {'health' => 'disabled'}
    assert_response :success
    assert_equal 1, assigns(:clients).length
  end
  test 'index stale' do
    get :index, {'health' => 'stale'}
    assert_response :success
    # The three _old clients
    assert_equal 3, assigns(:clients).length
  end
  test 'index pagination' do
    # I'm sure there's some idiotic reason why this doesn't work
    # (40-Client.count).times {|i| Client.create!(name: "client#{i}")}
    (40-Client.count).times {|i| c=Client.new; c.name="client#{i}"; c.save!}
    get :index
    assert_equal 30, assigns(:clients).length
    get :index, format: 'xml'
    assert_equal 40, assigns(:clients).length
  end
  test 'index search' do
    get :index, {'q' => {'name_eq' => 'healthy_recent'}}
    assert_response :success
    assert_equal 1, assigns(:clients).length
  end
  test 'index format html' do
    get :index
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'index format xml' do
    get :index, format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'clients', REXML::Document.new(response.body).root.name
  end

  test 'show default' do
    get :show, id: clients(:one)
    assert_response :success
    assert_equal clients(:one), assigns(:client)
  end
  test 'show timeline' do
    get :show, {id: clients(:one), timeline: '100'}
    assert_response :success
    assert_equal clients(:one), assigns(:client)
    assert_equal 100, assigns(:timeline)
  end
  test 'show format html' do
    get :show, id: clients(:one)
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'show format xml' do
    get :show, id: clients(:one), format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'client', REXML::Document.new(response.body).root.name
  end

  test 'should get new' do
    # We don't currently have a new view so this fails
    # get :new
    # assert_response :success
  end

  test 'should get edit' do
    # We don't currently have an edit view so this fails
    # get :edit, id: clients(:one)
    # assert_response :success
  end

  test 'should create client' do
    assert_difference('Client.count') do
      post :create, client: {name: 'newclient', status: 0, message: 'test'}
    end
    assert_redirected_to client_path(assigns(:client))
  end
  test 'create with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :create, client: {name: 'newclient', created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:client).created_at
  end

  test 'should update client' do
    patch :update, id: clients(:one), client: { name: 'differentclient' }
    assert_redirected_to client_path(assigns(:client))
  end
  test 'update with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :update, id: clients(:one), client: {created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:client).created_at
  end

  test 'should destroy client' do
    assert_difference('Client.count', -1) do
      delete :destroy, id: clients(:one)
    end
    assert_redirected_to clients_path
  end
end
