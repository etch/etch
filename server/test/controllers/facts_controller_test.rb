require 'test_helper'

class FactsControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:q)
    assert_not_nil assigns(:facts)
    assert_equal 2, assigns(:facts).length
  end
  test 'index pagination' do
    # I'm sure there's some idiotic reason why this doesn't work
    # (40-Fact.count).times {|i| Fact.create!(client_id: clients(:one))}
    (40-Fact.count).times {|i| f=Fact.new; f.client=clients(:one); f.key='key'; f.value='value'; f.save!}
    get :index
    assert_equal 30, assigns(:facts).length
    get :index, format: 'xml'
    assert_equal 40, assigns(:facts).length
  end
  test 'index search' do
    get :index, {'q' => {'client_name_eq' => clients(:one).name}}
    assert_response :success
    assert_equal 1, assigns(:facts).length
  end
  test 'index format html' do
    get :index
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'index format xml' do
    get :index, format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'facts', REXML::Document.new(response.body).root.name
  end

  test 'show default' do
    get :show, id: facts(:one)
    assert_response :success
    assert_equal facts(:one), assigns(:fact)
  end
  test 'show format html' do
    get :show, id: facts(:one)
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'show format xml' do
    get :show, id: facts(:one), format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'fact', REXML::Document.new(response.body).root.name
  end

  test 'should get new' do
    # We don't currently have a new view so this fails
    # get :new
    # assert_response :success
  end

  test 'should get edit' do
    # We don't currently have an edit view so this fails
    # get :edit, id: facts(:one)
    # assert_response :success
  end

  test 'should create fact' do
    assert_difference('Fact.count') do
      post :create, fact: {client_id: clients(:one), key: 'key', value: 'value'}
    end
    assert_redirected_to fact_path(assigns(:fact))
  end
  test 'create with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :create, fact: {client_id: clients(:one), key: 'key', value: 'value', created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:fact).created_at
  end

  test 'should update fact' do
    patch :update, id: facts(:one), fact: { file: '/path/to/file' }
    assert_redirected_to fact_path(assigns(:fact))
  end
  test 'update with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :update, id: facts(:one), fact: {created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:fact).created_at
  end

  test 'should destroy fact' do
    assert_difference('Fact.count', -1) do
      delete :destroy, id: facts(:one)
    end
    assert_redirected_to facts_path
  end
end
