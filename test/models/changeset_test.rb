require 'test_helper'

class ChangesetTest < ActiveSupport::TestCase
  api_fixtures

  def test_changeset_count
    assert_equal 7, Changeset.count
  end

  def test_from_xml_no_text
    no_text = ""
    check_error_attr(no_text, Mime::XML, /Must specify a string with one or more characters/)
  end

  def test_from_xml_no_changeset
    nocs = "<osm></osm>"
    check_error_attr(nocs, Mime::XML, /XML doesn't contain an osm\/changeset element/)
  end

  def test_from_xml_no_k_v
    nokv = "<osm><changeset><tag /></changeset></osm>"
    check_error_attr(nokv, Mime::XML, /tag is missing key/)
  end

  def test_from_xml_no_v
    no_v = "<osm><changeset><tag k='key' /></changeset></osm>"
    check_error_attr(no_v, Mime::XML, /tag is missing value/)
  end

  def test_from_xml_duplicate_k
    dupk = "<osm><changeset><tag k='dup' v='test' /><tag k='dup' v='value' /></changeset></osm>"
    check_error_attr(dupk, Mime::XML, /Element changeset\/ has duplicate tags with key dup/, OSM::APIDuplicateTagsError)
  end

  def test_from_xml_valid
    # Example taken from the Update section on the API_v0.6 docs on the wiki
    xml = "<osm><changeset><tag k=\"comment\" v=\"Just adding some streetnames and a restaurant\"/></changeset></osm>"
    assert_nothing_raised(OSM::APIBadXMLError) {
      Changeset.from_format(Mime::XML, xml, false)
    }
    assert_nothing_raised(OSM::APIBadXMLError) {
      Changeset.from_format(Mime::XML, xml, true)
    }
  end

  def test_from_json_no_text
    no_text = ""
    check_error_attr(no_text, Mime::JSON, /A JSON text must at least contain two octets/)
  end

  def test_from_json_valid
    # Example taken from the Update section on the API_v0.6 docs on the wiki
    json = "{\"tags\": {\"comment\": \"Just adding some streetnames and a restaurant\"}}"
    assert_nothing_raised(OSM::APIBadXMLError) {
      Changeset.from_format(Mime::JSON, json, false)
    }
    assert_nothing_raised(OSM::APIBadXMLError) {
      Changeset.from_format(Mime::JSON, json, true)
    }
  end

  #### utility methods ####

  # most attributes report faults in the same way, so we can abstract
  # that to a utility method
  def check_error_attr(content, format, message_regex, exception_class=OSM::APIBadXMLError)
    message_create = assert_raise(exception_class) {
      Changeset.from_format(format, content, true)
    }
    assert_match message_regex, message_create.message
    message_update = assert_raise(exception_class) {
      Changeset.from_format(format, content, false)
    }
    assert_match message_regex, message_update.message
  end

  # some attributes are optional on newly-created elements, but required
  # on updating elements.
  def check_error_attr_new_ok(content, format, message_regex, exception_class=OSM::APIBadXMLError)
    assert_nothing_raised(exception_class) {
      Changeset.from_format(format, content, true)
    }
    message_update = assert_raise(exception_class) {
      Changeset.from_format(format, content, false)
    }
    assert_match message_regex, message_update.message
  end
end
