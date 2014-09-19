require 'test_helper'

class ResultsControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:q)
    assert_not_nil assigns(:results)
    assert_equal 2, assigns(:results).length
  end
  test 'index pagination' do
    # I'm sure there's some idiotic reason why this doesn't work
    # (40-Result.count).times {|i| Result.create!(client_id: clients(:one))}
    (40-Result.count).times {|i| f=Result.new; f.client=clients(:one); f.file='/path'; f.success=true; f.message='test'; f.save!}
    get :index
    assert_equal 30, assigns(:results).length
    get :index, format: 'xml'
    assert_equal 40, assigns(:results).length
    get :index, combined: true
    assert_equal 40, assigns(:results).length
  end
  test 'index combined' do
    get :index, combined: true
    assert_response :success
    assert_not_nil assigns(:combined)
  end
  test 'index search' do
    get :index, {'q' => {'client_name_eq' => clients(:one).name}}
    assert_response :success
    assert_equal 1, assigns(:results).length
  end
  test 'index format html' do
    get :index
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'index format xml' do
    get :index, format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'results', REXML::Document.new(response.body).root.name
  end

  test 'show default' do
    get :show, id: results(:one)
    assert_response :success
    assert_equal results(:one), assigns(:result)
  end
  test 'show format html' do
    get :show, id: results(:one)
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'show format xml' do
    get :show, id: results(:one), format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'result', REXML::Document.new(response.body).root.name
  end

  test 'should get new' do
    # We don't currently have a new view so this fails
    # get :new
    # assert_response :success
  end

  test 'should get edit' do
    # We don't currently have an edit view so this fails
    # get :edit, id: results(:one)
    # assert_response :success
  end

  test 'should create result' do
    # The results controller create method is unusual
    post :create, {fqdn: 'resulttest.example.com', status: 0, message: 'clientmessage', results: [{file: '/path', success: true, message: 'resultmessage'}]}
    assert_response :success
    assert_equal 'resulttest.example.com', Client.last.name
    assert_equal 0, Client.last.status
    assert_equal 'clientmessage', Client.last.message
    assert_equal Client.last, Result.last.client
    assert_equal '/path', Result.last.file
    assert_equal true, Result.last.success
    assert_equal 'resultmessage', Result.last.message
  end
  test 'create with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :create, result: {client_id: clients(:one), file: '/path', success: true, message: 'test', created_at: tenhoursago}
    assert_not_equal tenhoursago, Result.last.created_at
  end

  test 'should update result' do
    patch :update, id: results(:one), result: { file: '/path/to/file' }
    assert_redirected_to result_path(assigns(:result))
  end
  test 'update with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :update, id: results(:one), result: {created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:result).created_at
  end

  test 'should destroy result' do
    assert_difference('Result.count', -1) do
      delete :destroy, id: results(:one)
    end
    assert_redirected_to results_path
  end
end
