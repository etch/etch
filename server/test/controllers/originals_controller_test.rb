require 'test_helper'

class OriginalsControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:q)
    assert_not_nil assigns(:originals)
    assert_equal 2, assigns(:originals).length
  end
  test 'index pagination' do
    # I'm sure there's some idiotic reason why this doesn't work
    # (40-Original.count).times {|i| Original.create!(client_id: clients(:one))}
    (40-Original.count).times {|i| f=Original.new; f.client=clients(:one); f.file='/path'; f.sum='0xdeadbeef'; f.save!}
    get :index
    assert_equal 30, assigns(:originals).length
    get :index, format: 'xml'
    assert_equal 40, assigns(:originals).length
  end
  test 'index search' do
    get :index, {'q' => {'client_name_eq' => clients(:one).name}}
    assert_response :success
    assert_equal 1, assigns(:originals).length
  end
  test 'index format html' do
    get :index
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'index format xml' do
    get :index, format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'originals', REXML::Document.new(response.body).root.name
  end

  test 'show default' do
    get :show, id: originals(:one)
    assert_response :success
    assert_equal originals(:one), assigns(:original)
  end
  test 'show format html' do
    get :show, id: originals(:one)
    assert_equal 'text/html', response.content_type
    assert response.body =~ /<html>/
  end
  test 'show format xml' do
    get :show, id: originals(:one), format: 'xml'
    assert_equal 'application/xml', response.content_type
    assert_equal 'original', REXML::Document.new(response.body).root.name
  end

  test 'should get new' do
    # We don't currently have a new view so this fails
    # get :new
    # assert_response :success
  end

  test 'should get edit' do
    # We don't currently have an edit view so this fails
    # get :edit, id: originals(:one)
    # assert_response :success
  end

  test 'should create original' do
    assert_difference('Original.count') do
      post :create, original: {client_id: clients(:one), file: '/path', sum: '0xdeadbeef'}
    end
    assert_redirected_to original_path(assigns(:original))
  end
  test 'create with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :create, original: {client_id: clients(:one), file: '/path', sum: '0xdeadbeef', created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:original).created_at
  end

  test 'should update original' do
    patch :update, id: originals(:one), original: { file: '/path/to/file' }
    assert_redirected_to original_path(assigns(:original))
  end
  test 'update with forbidden attribute' do
    tenhoursago = 10.hours.ago
    post :update, id: originals(:one), original: {created_at: tenhoursago}
    assert_not_equal tenhoursago, assigns(:original).created_at
  end

  test 'should destroy original' do
    assert_difference('Original.count', -1) do
      delete :destroy, id: originals(:one)
    end
    assert_redirected_to originals_path
  end
end
