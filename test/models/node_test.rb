require 'test_helper'

class NodeTest < ActiveSupport::TestCase
  api_fixtures
  
  def test_node_count
    assert_equal 18, Node.count
  end

  def test_node_too_far_north
    invalid_node_test(:node_too_far_north)
  end
  
  def test_node_north_limit
    valid_node_test(:node_north_limit)
  end
  
  def test_node_too_far_south
    invalid_node_test(:node_too_far_south)
  end
  
  def test_node_south_limit
    valid_node_test(:node_south_limit)
  end
  
  def test_node_too_far_west
    invalid_node_test(:node_too_far_west)
  end
  
  def test_node_west_limit
    valid_node_test(:node_west_limit)
  end
  
  def test_node_too_far_east
    invalid_node_test(:node_too_far_east)
  end
  
  def test_node_east_limit
    valid_node_test(:node_east_limit)
  end
  
  def test_totally_wrong
    invalid_node_test(:node_totally_wrong)
  end
  
  # This helper method will check to make sure that a node is within the world, and
  # has the the same lat, lon and timestamp than what was put into the db by 
  # the fixture
  def valid_node_test(nod)
    node = current_nodes(nod)
    dbnode = Node.find(node.id)
    assert_equal dbnode.lat, node.latitude.to_f/SCALE
    assert_equal dbnode.lon, node.longitude.to_f/SCALE
    assert_equal dbnode.changeset_id, node.changeset_id
    assert_equal dbnode.timestamp, node.timestamp
    assert_equal dbnode.version, node.version
    assert_equal dbnode.visible, node.visible
    #assert_equal node.tile, QuadTile.tile_for_point(node.lat, node.lon)
    assert node.valid?
  end
  
  # This helper method will check to make sure that a node is outwith the world, 
  # and has the same lat, lon and timesamp than what was put into the db by the
  # fixture
  def invalid_node_test(nod)
    node = current_nodes(nod)
    dbnode = Node.find(node.id)
    assert_equal dbnode.lat, node.latitude.to_f/SCALE
    assert_equal dbnode.lon, node.longitude.to_f/SCALE
    assert_equal dbnode.changeset_id, node.changeset_id
    assert_equal dbnode.timestamp, node.timestamp
    assert_equal dbnode.version, node.version
    assert_equal dbnode.visible, node.visible
    #assert_equal node.tile, QuadTile.tile_for_point(node.lat, node.lon)
    assert_equal false, dbnode.valid?
  end
  
  # Check that you can create a node and store it
  def test_create
    node_template = Node.new(
      :latitude => 12.3456,
      :longitude => 65.4321,
      :changeset_id => changesets(:normal_user_first_change).id,
      :visible => 1, 
      :version => 1
    )
    assert node_template.create_with_history(users(:normal_user))

    node = Node.find(node_template.id)
    assert_not_nil node
    assert_equal node_template.latitude, node.latitude
    assert_equal node_template.longitude, node.longitude
    assert_equal node_template.changeset_id, node.changeset_id
    assert_equal node_template.visible, node.visible
    assert_equal node_template.timestamp.to_i, node.timestamp.to_i

    assert_equal OldNode.where(:node_id => node_template.id).count, 1
    old_node = OldNode.where(:node_id => node_template.id).first
    assert_not_nil old_node
    assert_equal node_template.latitude, old_node.latitude
    assert_equal node_template.longitude, old_node.longitude
    assert_equal node_template.changeset_id, old_node.changeset_id
    assert_equal node_template.visible, old_node.visible
    assert_equal node_template.tags, old_node.tags
    assert_equal node_template.timestamp.to_i, old_node.timestamp.to_i
  end

  def test_update
    node_template = Node.find(current_nodes(:visible_node).id)
    assert_not_nil node_template

    assert_equal OldNode.where(:node_id => node_template.id).count, 1
    node = Node.find(node_template.id)
    assert_not_nil node

    node_template.latitude = 12.3456
    node_template.longitude = 65.4321
    #node_template.tags = "updated=yes"
    assert node.update_from(node_template, users(:normal_user))

    node = Node.find(node_template.id)
    assert_not_nil node
    assert_equal node_template.latitude, node.latitude
    assert_equal node_template.longitude, node.longitude
    assert_equal node_template.changeset_id, node.changeset_id
    assert_equal node_template.visible, node.visible
    #assert_equal node_template.tags, node.tags

    assert_equal OldNode.where(:node_id => node_template.id).count, 2
    old_node = OldNode.where(:node_id => node_template.id, :version => 2).first
    assert_not_nil old_node
    assert_equal node_template.latitude, old_node.latitude
    assert_equal node_template.longitude, old_node.longitude
    assert_equal node_template.changeset_id, old_node.changeset_id
    assert_equal node_template.visible, old_node.visible
    #assert_equal node_template.tags, old_node.tags
  end

  def test_delete
    node_template = Node.find(current_nodes(:visible_node))
    assert_not_nil node_template

    assert_equal OldNode.where(:node_id => node_template.id).count, 1
    node = Node.find(node_template.id)
    assert_not_nil node

    assert node.delete_with_history!(node_template, users(:normal_user))

    node = Node.find(node_template.id)
    assert_not_nil node
    assert_equal node_template.latitude, node.latitude
    assert_equal node_template.longitude, node.longitude
    assert_equal node_template.changeset_id, node.changeset_id
    assert_equal false, node.visible
    #assert_equal node_template.tags, node.tags

    assert_equal OldNode.where(:node_id => node_template.id).count, 2
    old_node = OldNode.where(:node_id => node_template.id, :version => 2).first
    assert_not_nil old_node
    assert_equal node_template.latitude, old_node.latitude
    assert_equal node_template.longitude, old_node.longitude
    assert_equal node_template.changeset_id, old_node.changeset_id
    assert_equal false, old_node.visible
    #assert_equal node_template.tags, old_node.tags
  end
  
  def test_from_xml_no_id
    lat = 56.7
    lon = -2.3
    changeset = 2
    version = 1
    noid = "<osm><node lat='#{lat}' lon='#{lon}' changeset='#{changeset}' version='#{version}' /></osm>"
    check_error_attr_new_ok(noid, Mime::XML, /ID is required when updating./)
  end
  
  def test_from_xml_no_lat
    nolat = "<osm><node id='1' lon='23.3' changeset='2' version='23' /></osm>"
    check_error_attr(nolat, Mime::XML, /lat missing/)
  end
  
  def test_from_xml_no_lon
    nolon = "<osm><node id='1' lat='23.1' changeset='2' version='23' /></osm>"
    check_error_attr(nolon, Mime::XML, /lon missing/)
  end

  def test_from_xml_no_changeset_id
    nocs = "<osm><node id='123' lon='23.23' lat='23.1' version='23' /></osm>"
    check_error_attr(nocs, Mime::XML, /Changeset id is missing/)
  end
  
  def test_from_xml_no_version
    no_version = "<osm><node id='123' lat='23' lon='23' changeset='23' /></osm>"
    check_error_attr_new_ok(no_version, Mime::XML, /Version is required when updating/)
  end
  
  def test_from_xml_double_lat
    double_lat = "<osm><node id='123' lon='23.23' lat='23.1' lat='12' changeset='23' version='23' /></osm>"
    check_error_attr(double_lat, Mime::XML, /Fatal error: Attribute lat redefined at/)
  end
  
  def test_from_xml_id_zero
    id_list = ["", "0", "00", "0.0", "a"]
    id_list.each do |id|
      zero_id = "<osm><node id='#{id}' lat='12.3' lon='12.3' changeset='33' version='23' /></osm>"
      check_error_attr_new_ok(zero_id, Mime::XML, /ID of node cannot be zero when updating/, OSM::APIBadUserInput)
    end
  end
  
  def test_from_xml_no_text
    check_error_attr("", Mime::XML, /Must specify a string with one or more characters/)
  end
  
  def test_from_xml_no_node
    no_node = "<osm></osm>"
    check_error_attr(no_node, Mime::XML, /XML doesn't contain an osm\/node element/)
  end
  
  def test_from_xml_no_k_v
    nokv = "<osm><node id='23' lat='12.3' lon='23.4' changeset='12' version='23'><tag /></node></osm>"
    check_error_attr(nokv, Mime::XML, /tag is missing key/)
  end
  
  def test_from_xml_no_v
    no_v = "<osm><node id='23' lat='23.43' lon='23.32' changeset='23' version='32'><tag k='key' /></node></osm>"
    check_error_attr(no_v, Mime::XML, /tag is missing value/)
  end
  
  def test_from_xml_duplicate_k
    dupk = "<osm><node id='23' lat='23.2' lon='23' changeset='34' version='23'><tag k='dup' v='test' /><tag k='dup' v='tester' /></node></osm>"
    message_create = assert_raise(OSM::APIDuplicateTagsError) {
      Node.from_format(Mime::XML, dupk, true)
    }
    assert_equal "Element node/ has duplicate tags with key dup", message_create.message
    message_update = assert_raise(OSM::APIDuplicateTagsError) {
      Node.from_format(Mime::XML, dupk, false)
    }
    assert_equal "Element node/23 has duplicate tags with key dup", message_update.message
  end

  def test_from_json_no_id
    noid = {'nodes'=>{'lat' => 56.7, 'lon' => -2.3, 'changeset' => 2, 'version' => 1}}.to_json
    check_error_attr_new_ok(noid, Mime::JSON, /ID is required when updating./)
  end

  def test_from_json_no_lat
    nolat = {'nodes'=>{'id' => 1, 'lon' => 23.3, 'changeset' => 2, 'version' => 23}}.to_json
    check_error_attr(nolat, Mime::JSON, /lat missing/)
  end

  def test_from_json_no_lon
    nolon = {'nodes'=>{'id' => 1, 'lat' => 23.1, 'changeset' => 2, 'version' => 23}}.to_json
    check_error_attr(nolon, Mime::JSON, /lon missing/)
  end

  def test_from_json_no_changeset_id
    nocs = {'nodes'=>{'id' => 123, 'lon' => 23.23, 'lat' => 23.1, 'version' => 23}}.to_json
    check_error_attr(nocs, Mime::JSON, /Changeset id is missing/)
  end

  def test_from_json_no_version
    no_version = {'nodes'=>{'id' => 123, 'lat' => 23, 'lon' => 23, 'changeset' => 23}}.to_json
    check_error_attr_new_ok(no_version, Mime::JSON, /Version is required when updating/)
  end

  def test_to_json
    node = current_nodes(:used_node_1)

    data = JSON.parse(node.to_format(Mime::JSON))

    assert_equal(Array, data['nodes'].class)
    assert_equal(1, data['nodes'].length)
    jnode = data['nodes'][0]
    assert_equal(node.id, jnode['id'])
    assert_equal(node.version, jnode['version'])
    assert_equal(node.changeset.id, jnode['changeset'])
    assert_equal(node.lat, jnode['lat'])
    assert_equal(node.lon, jnode['lon'])
    assert_equal(node.visible, jnode['visible'])
    assert_equal(node.timestamp, Time.parse(jnode['timestamp']))
    assert_equal(node.tags, jnode['tags'])
    assert_equal(node.changeset.user.id, jnode['uid'])
    assert_equal(node.changeset.user.display_name, jnode['user'])
  end

  def test_to_json_respects_private_data
    # visible_node is by a non-public user, so shouldn't show user ID or name. in JSON
    # these should be set to null, which is different behaviour from XML. in XML they
    # are just not present.
    node = current_nodes(:visible_node)

    data = JSON.parse(node.to_format(Mime::JSON))

    assert_equal(Array, data['nodes'].class)
    assert_equal(1, data['nodes'].length)
    jnode = data['nodes'][0]
    assert_equal(node.id, jnode['id'])
    assert_equal(node.version, jnode['version'])
    assert_equal(node.changeset.id, jnode['changeset'])
    assert_equal(node.lat, jnode['lat'])
    assert_equal(node.lon, jnode['lon'])
    assert_equal(node.visible, jnode['visible'])
    assert_equal(node.timestamp, Time.parse(jnode['timestamp']))
    assert_equal(node.tags, jnode['tags'])
    assert_equal(true, jnode.has_key?('uid'))
    assert_equal(nil, jnode['uid'])
    assert_equal(true, jnode.has_key?('user'))
    assert_equal(nil, jnode['user'])
  end

  def test_to_xml
    node = current_nodes(:used_node_1)

    data = XML::Parser.string(node.to_format(Mime::XML).to_s).parse

    nodes = data.root.children.select {|n| n.element?}
    assert_equal(1, nodes.length)
    xnode = nodes[0]
    assert_equal(node.id, xnode['id'].to_i)
    assert_equal(node.version, xnode['version'].to_i)
    assert_equal(node.changeset.id, xnode['changeset'].to_i)
    assert_equal(node.lat, xnode['lat'].to_f)
    assert_equal(node.lon, xnode['lon'].to_f)
    assert_equal(node.visible, xnode['visible'] == 'true')
    assert_equal(node.timestamp, Time.parse(xnode['timestamp']))
    xtags = Hash[xnode.children.select {|n| n.element?}.map {|n| [n['k'], n['v']]}]
    assert_equal(node.tags, xtags)
    assert_equal(node.changeset.user.id, xnode['uid'].to_i)
    assert_equal(node.changeset.user.display_name, xnode['user'])
  end

  def test_to_xml_respects_private_data
    # visible_node is by a non-public user, so shouldn't show user ID or name
    node = current_nodes(:visible_node)

    data = XML::Parser.string(node.to_format(Mime::XML).to_s).parse

    nodes = data.root.children.select {|n| n.element?}
    assert_equal(1, nodes.length)
    xnode = nodes[0]
    assert_equal(node.id, xnode['id'].to_i)
    assert_equal(node.version, xnode['version'].to_i)
    assert_equal(node.changeset.id, xnode['changeset'].to_i)
    assert_equal(node.lat, xnode['lat'].to_f)
    assert_equal(node.lon, xnode['lon'].to_f)
    assert_equal(node.visible, xnode['visible'] == 'true')
    assert_equal(node.timestamp, Time.parse(xnode['timestamp']))
    xtags = Hash[xnode.children.select {|n| n.element?}.map {|n| [n['k'], n['v']]}]
    assert_equal(node.tags, xtags)
    assert_equal(nil, xnode['uid'])
    assert_equal(nil, xnode['user'])
  end

  ## NOTE: the "double attribute" errors which we raise in XML mode don't apply here
  ## the last value will silently overwrite any previous values. not sure if this should
  ## be considered a bug, but needs reporting in the dev docs.

  def test_from_json_id_zero
    # first, testing some things which are 'zero' or otherwise invalid due to being
    # invalid JSON
    id_list = ["", "00", "a"]
    id_list.each do |id|
      zero_id = '{"nodes":{"id":' + id + ',"lat":12.3,"lon":12.3,"changeset":33,"version":33}}'
      check_error_attr(zero_id, Mime::JSON, /Cannot parse valid node from xml string/)
    end

    # second, testing some things which are also 'zero', but should be rejected at
    # a later check due to them being 'zero'.
    id_list = ["0", "0.0", "\"\"", "\"0\"", "\"00\"", "\"0.0\"", "\"a\""]
    id_list.each do |id|
      zero_id = '{"nodes":{"id":' + id + ',"lat":12.3,"lon":12.3,"changeset":33,"version":33}}'
      check_error_attr_new_ok(zero_id, Mime::JSON, /ID of node cannot be zero when updating/, OSM::APIBadUserInput)
    end
  end

  def test_from_json_no_text
    check_error_attr("", Mime::JSON, /A JSON text must at least contain two octets/)
  end

  # check that whether an item is in the JSON as a string or as a number
  # doesn't make any difference to whether the node object parses.
  def test_from_json_quoting_unimportant
    data = {'id' => 123, 'lon' => 23.23, 'lat' => 23.1, 'changeset' => 23, 'version' => 23}
    data.keys.each do |k|
      data_quoted = data.clone
      data_quoted[k] = data_quoted[k].to_s
      assert_nothing_raised(OSM::APIBadUserInput) {
        Node.from_format(Mime::JSON, {'nodes'=>data_quoted}.to_json, true)
      }
      assert_nothing_raised(OSM::APIBadUserInput) {
        Node.from_format(Mime::JSON, {'nodes'=>data_quoted}.to_json, false)
      }
    end
  end

  #### utility methods ####

  # most attributes report faults in the same way, so we can abstract
  # that to a utility method
  def check_error_attr(content, format, message_regex)
    message_create = assert_raise(OSM::APIBadXMLError) {
      Node.from_format(format, content, true)
    }
    assert_match message_regex, message_create.message
    message_update = assert_raise(OSM::APIBadXMLError) {
      Node.from_format(format, content, false)
    }
    assert_match message_regex, message_update.message
  end

  # some attributes are optional on newly-created elements, but required
  # on updating elements.
  def check_error_attr_new_ok(content, format, message_regex, exception_class=OSM::APIBadXMLError)
    assert_nothing_raised(exception_class) {
      Node.from_format(format, content, true)
    }
    message_update = assert_raise(exception_class) {
      Node.from_format(format, content, false)
    }
    assert_match message_regex, message_update.message
  end

  def test_node_tags
    node = current_nodes(:node_with_versions)
    tags = Node.find(node.id).node_tags.order(:k)
    assert_equal 2, tags.count
    assert_equal "testing", tags[0].k 
    assert_equal "added in node version 3", tags[0].v
    assert_equal "testing two", tags[1].k
    assert_equal "modified in node version 4", tags[1].v
  end

  def test_tags
    node = current_nodes(:node_with_versions)
    tags = Node.find(node.id).tags
    assert_equal 2, tags.size
    assert_equal "added in node version 3", tags["testing"]
    assert_equal "modified in node version 4", tags["testing two"]
  end
end
