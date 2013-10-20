require File.dirname(__FILE__) + '/../test_helper'

class WayTest < ActiveSupport::TestCase
  api_fixtures

  # Check that we have the correct number of currnet ways in the db
  # This will need to updated whenever the current_ways.yml is updated
  def test_db_count
    assert_equal 6, Way.count
  end
  
  def test_bbox
    node = current_nodes(:used_node_1)
    [ :visible_way,
      :invisible_way,
      :used_way ].each do |way_symbol|
      way = current_ways(way_symbol)
      assert_equal node.bbox.min_lon, way.bbox.min_lon, 'min_lon'
      assert_equal node.bbox.min_lat, way.bbox.min_lat, 'min_lat'
      assert_equal node.bbox.max_lon, way.bbox.max_lon, 'max_lon'
      assert_equal node.bbox.max_lat, way.bbox.max_lat, 'max_lat'
    end
  end
  
  # Check that the preconditions fail when you are over the defined limit of 
  # the maximum number of nodes in each way.
  def test_max_nodes_per_way_limit
    # Take one of the current ways and add nodes to it until we are near the limit
    way = Way.find(current_ways(:visible_way).id)
    assert way.valid?
    # it already has 1 node
    1.upto((MAX_NUMBER_OF_WAY_NODES) / 2) {
      way.add_nd_num(current_nodes(:used_node_1).id)
      way.add_nd_num(current_nodes(:used_node_2).id)
    }
    way.save
    #print way.nds.size
    assert way.valid?
    way.add_nd_num(current_nodes(:visible_node).id)
    assert way.valid?
  end
  
  def test_from_xml_no_id
    noid = "<osm><way version='12' changeset='23' /></osm>"
    check_error_attr_new_ok(noid, Mime::XML, /ID is required when updating/)
  end
  
  def test_from_xml_no_changeset_id
    nocs = "<osm><way id='123' version='23' /></osm>"
    check_error_attr(nocs, Mime::XML, /Changeset id is missing/)
  end
  
  def test_from_xml_no_version
    no_version = "<osm><way id='123' changeset='23' /></osm>"
    check_error_attr_new_ok(no_version, Mime::XML, /Version is required when updating/)
  end

  def test_from_xml_id_zero
    id_list = ["", "0", "00", "0.0", "a"]
    id_list.each do |id|
      zero_id = "<osm><way id='#{id}' changeset='33' version='23' /></osm>"
      check_error_attr_new_ok(zero_id, Mime::XML, /ID of way cannot be zero when updating/, OSM::APIBadUserInput)
    end
  end
  
  def test_from_xml_no_text
    check_error_attr("", Mime::XML, /Must specify a string with one or more characters/)
  end
  
  def test_from_xml_no_k_v
    nokv = "<osm><way id='23' changeset='23' version='23'><tag /></way></osm>"
    check_error_attr(nokv, Mime::XML, /tag is missing key/)
  end
  
  def test_from_xml_no_v
    no_v = "<osm><way id='23' changeset='23' version='23'><tag k='key' /></way></osm>"
    check_error_attr(no_v, Mime::XML, /tag is missing value/)
  end
  
  def test_from_xml_duplicate_k
    dupk = "<osm><way id='23' changeset='23' version='23'><tag k='dup' v='test' /><tag k='dup' v='tester' /></way></osm>"
    message_create = assert_raise(OSM::APIDuplicateTagsError) {
      Way.from_format(Mime::XML, dupk, true)
    }
    assert_equal "Element way/ has duplicate tags with key dup", message_create.message
    message_update = assert_raise(OSM::APIDuplicateTagsError) {
      Way.from_format(Mime::XML, dupk, false)
    }
    assert_equal "Element way/23 has duplicate tags with key dup", message_update.message
  end

  def test_from_json_no_id
    noid = {'ways'=>{'changeset' => 2, 'version' => 1}}.to_json
    check_error_attr_new_ok(noid, Mime::JSON, /ID is required when updating/)
  end

  def test_from_json_no_changeset_id
    nocs = {'ways'=>{'id' => 123, 'version' => 23}}.to_json
    check_error_attr(nocs, Mime::JSON, /Changeset id is missing/)
  end

  def test_from_json_no_version
    no_version = {'ways'=>{'id' => 123, 'changeset' => 23}}.to_json
    check_error_attr_new_ok(no_version, Mime::JSON, /Version is required when updating/)
  end

  ## NOTE: the "double attribute" errors which we raise in XML mode don't apply here
  ## the last value will silently overwrite any previous values. not sure if this should
  ## be considered a bug, but needs reporting in the dev docs.

  def test_from_json_id_zero
    # first, testing some things which are 'zero' or otherwise invalid due to being
    # invalid JSON
    id_list = ["", "00", "a"]
    id_list.each do |id|
      zero_id = '{"ways":{"id":' + id + ',"changeset":33,"version":33}}'
      check_error_attr(zero_id, Mime::JSON, /Cannot parse valid way from xml string/)
    end

    # second, testing some things which are also 'zero', but should be rejected at
    # a later check due to them being 'zero'.
    id_list = ["0", "0.0", "\"\"", "\"0\"", "\"00\"", "\"0.0\"", "\"a\""]
    id_list.each do |id|
      zero_id = '{"ways":{"id":' + id + ',"changeset":33,"version":33}}'
      check_error_attr_new_ok(zero_id, Mime::JSON, /ID of way cannot be zero when updating/, OSM::APIBadUserInput)
    end
  end

  def test_from_json_no_text
    check_error_attr("", Mime::JSON, /A JSON text must at least contain two octets/)
  end

  # check that whether an item is in the JSON as a string or as a number
  # doesn't make any difference to whether the way object parses.
  def test_from_json_quoting_unimportant
    data = {'id' => 123, 'changeset' => 23, 'version' => 23}
    data.keys.each do |k|
      data_quoted = data.clone
      data_quoted[k] = data_quoted[k].to_s
      assert_nothing_raised(OSM::APIBadUserInput) {
        Way.from_format(Mime::JSON, {'ways'=>data_quoted}.to_json, true)
      }
      assert_nothing_raised(OSM::APIBadUserInput) {
        Way.from_format(Mime::JSON, {'ways'=>data_quoted}.to_json, false)
      }
    end
  end

  def test_to_json
    way = current_ways(:visible_way)

    data = JSON.parse(way.to_format(Mime::JSON))

    assert_equal(Array, data['ways'].class)
    assert_equal(1, data['ways'].length)
    jway = data['ways'][0]
    assert_equal(way.id, jway['id'])
    assert_equal(way.version, jway['version'])
    assert_equal(way.changeset.id, jway['changeset'])
    assert_equal(way.changeset.user.id, jway['uid'])
    assert_equal(way.changeset.user.display_name, jway['user'])
    assert_equal(way.visible, jway['visible'])
    assert_equal(way.timestamp, Time.parse(jway['timestamp']))
    assert_equal(way.tags, jway['tags'])
    assert_equal(way.nds, jway['nds'])
  end

  #### utility methods ####

  # most attributes report faults in the same way, so we can abstract
  # that to a utility method
  def check_error_attr(content, format, message_regex)
    message_create = assert_raise(OSM::APIBadXMLError) {
      Way.from_format(format, content, true)
    }
    assert_match message_regex, message_create.message
    message_update = assert_raise(OSM::APIBadXMLError) {
      Way.from_format(format, content, false)
    }
    assert_match message_regex, message_update.message
  end

  # some attributes are optional on newly-created elements, but required
  # on updating elements.
  def check_error_attr_new_ok(content, format, message_regex, exception_class=OSM::APIBadXMLError)
    assert_nothing_raised(exception_class) {
      Way.from_format(format, content, true)
    }
    message_update = assert_raise(exception_class) {
      Way.from_format(format, content, false)
    }
    assert_match message_regex, message_update.message
  end
end
