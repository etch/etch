require 'test_helper'

class EtchConfigsControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:q)
    assert_not_nil assigns(:etch_configs)
    assert_equal 2, assigns(:etch_configs).length
  end
  test 'index pagination' do
    # I'm sure there's some idiotic reason why this doesn't work
    # (40-EtchConfig.count).times {|i| EtchConfig.create!(client_id: clients(:one))}
    (40-EtchConfig.count).times {|i| c=EtchConfig.new; c.client=clients(:one); c.file='/path'; c.config='data'; c.save!}
    get :index
    assert_equal 30, assigns(:etch_configs).length
    get :index, format: 'xml'
    assert_equal 40, assigns(:etch_configs).length
  end
  test 'index search' do
    get :index, {'q' => {'client_name_eq' => clients(:one).name}}
    assert_response :success
    assert_equal 1, assigns(:etch_configs).length
  end
  test 'index format html' do
    get :index
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'index format xml' do
    get :index, format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'etch_configs', REXML::Document.new(response.body).root.name
  end

  test 'show default' do
    get :show, id: etch_configs(:one)
    assert_response :success
    assert_equal etch_configs(:one), assigns(:etch_config)
  end
  test 'show format html' do
    get :show, id: etch_configs(:one)
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'show format xml' do
    get :show, id: etch_configs(:one), format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'etch_config', REXML::Document.new(response.body).root.name
  end

  test 'should get new' do
    # We don't currently have a new view so this fails
    # get :new
    # assert_response :success
  end

  test 'should get edit' do
    # We don't currently have an edit view so this fails
    # get :edit, id: etch_configs(:one)
    # assert_response :success
  end

  test 'should create etch config' do
    assert_difference('EtchConfig.count') do
      post :create, etch_config: {client_id: clients(:one), file: '/path', config: 'data'}
    end
    assert_redirected_to etch_config_path(assigns(:etch_config))
  end
  test 'create with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :create, etch_config: {client_id: clients(:one), file: '/path', config: 'data', created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:etch_config).created_at
  end

  test 'should update etch config' do
    patch :update, id: etch_configs(:one), etch_config: { file: '/path/to/file' }
    assert_redirected_to etch_config_path(assigns(:etch_config))
  end
  test 'update with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :update, id: etch_configs(:one), etch_config: {created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:etch_config).created_at
  end

  test 'should destroy etch config' do
    assert_difference('EtchConfig.count', -1) do
      delete :destroy, id: etch_configs(:one)
    end
    assert_redirected_to etch_configs_path
  end
end
