require 'test_helper'

class SearchControllerTest < ActionController::TestCase
  api_fixtures

  ##
  # test all routes which lead to this controller
  def test_routes
    assert_routing(
      { :path => "/api/0.6/search", :method => :get },
      { :controller => "search", :action => "search_all" }
    )
    assert_routing(
      { :path => "/api/0.6/nodes/search", :method => :get },
      { :controller => "search", :action => "search_nodes" }
    )
    assert_routing(
      { :path => "/api/0.6/ways/search", :method => :get },
      { :controller => "search", :action => "search_ways" }
    )
    assert_routing(
      { :path => "/api/0.6/relations/search", :method => :get },
      { :controller => "search", :action => "search_relations" }
    )
  end

  ##
  # test that searching a tag on all types fails because
  # searching on nodes is unavailable.
  def test_search_controller_all
    get :search_all, :type => 'test', :value => 'yes'
    assert_response :service_unavailable, "Search including nodes should have been unavailable"
  end

  ##
  # test that searching a tag on nodes fails.
  def test_search_controller_nodes
    get :search_nodes, :type => 'test', :value => 'yes'
    assert_response :service_unavailable, "Search including nodes should have been unavailable"
  end

  ##
  # test that searching a tag on ways gets the results we
  # expect from the fixtures.
  def test_search_controller_ways
    get :search_ways, :type => 'test', :value => 'yes'
    assert_response :success, "Search response should have been successful"

    # included nodes
    assert_select "osm>node", 1
    assert_select "osm>node[id=3]", 1
    
    assert_select "osm>way", 3
    assert_select "osm>way[id=1]", 1
    assert_select "osm>way[id=2]", 1
    assert_select "osm>way[id=3]", 1
    assert_select "osm>relation", 0
  end

  ##
  # test that searching a tag on relations gets the results we
  # expect from the fixtures.
  def test_search_controller_relations
    get :search_relations, :type => 'test', :value => 'yes'
    assert_response :success, "Search response should have been successful"

    assert_select "osm>node", 0
    assert_select "osm>way", 0
    assert_select "osm>relation", 3
    assert_select "osm>relation[id=1]", 1
    assert_select "osm>relation[id=2]", 1
    assert_select "osm>relation[id=3]", 1
  end

  ##
  # test JSON support
  def test_search_controller_ways_json
    @request.headers["Accept"] = "application/json"
    get :search_ways, :type => 'test', :value => 'yes'
    assert_response :success, "Search response should have been successful"

    data = JSON.parse(@response.body)
    assert_equal [3], data['nodes'].map {|n| n['id']}
    assert_equal [1,2,3], data['ways'].map {|w| w['id']}
    assert_equal [], data['relations']
  end
end
