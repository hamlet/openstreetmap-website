module OSM::Format
  
  class Common
    def initialize(changeset_cache = {}, user_display_name_cache = {})
      @changeset_cache = changeset_cache
      @user_display_name_cache = user_display_name_cache
    end

    def self.ordered_nodes(raw_nodes, visible_nodes = nil)
      ordered_nodes = []
      raw_nodes.each do |nd|
        if visible_nodes
          # if there is a list of visible nodes then use that to weed out deleted nodes
          if visible_nodes[nd.node_id]
            ordered_nodes[nd.sequence_id] = nd.node_id.to_i
          end
        else
          # otherwise, manually go to the db to check things
          if nd.node and nd.node.visible?
            ordered_nodes[nd.sequence_id] = nd.node_id.to_i
          end
        end
      end
      ordered_nodes.select {|nd_id| nd_id and (nd_id != 0)}
    end

    def obj_display_name(obj)
      if obj.changeset.user.data_public?
        obj.changeset.user.display_name
      else
        nil
      end
    end

    def common_attributes(id, obj)
      self['id'] = id
      self['visible'] = obj.visible
      self['timestamp'] = obj.timestamp.xmlschema
      self['version'] = obj.version
      self['changeset'] = obj.changeset_id
      
      user_id = (@changeset_cache[obj.changeset_id] ||= obj.changeset.user_id)
      display_name = (@user_display_name_cache[user_id] ||= obj_display_name(obj))
      
      if display_name.nil?
        self['user'] = nil
        self['uid'] = nil
      else
        self['user'] = display_name
        self['uid'] = user_id
      end

      self['redacted'] = obj.redaction.id if obj.redacted?
    end    
  end

  class XMLWrapper < Common
    def initialize(name, changeset_cache = {}, user_display_name_cache = {})
      super(changeset_cache, user_display_name_cache)
      @xml = XML::Node.new(name)
    end

    def []=(k, v)
      @xml[k.to_s] = v.to_s unless v.nil?
    end

    def tags=(hash_tags)
      hash_tags.each do |k, v|
        e = XML::Node.new 'tag'
        e['k'] = k.to_s
        e['v'] = v.to_s
        @xml << e
      end
    end

    def nds(raw_nds, visible_nodes = nil)
      Common.ordered_nodes(raw_nds, visible_nodes).each do |node_id|
        e = XML::Node.new 'nd'
        e['ref'] = node_id.to_s
        @xml << e
      end
    end

    def members=(raw_members)
      raw_members.each do |member|
        e = XML::Node.new 'member'
        e['type'] = member.member_type.downcase
        e['ref'] = member.member_id.to_s 
        e['role'] = member.member_role
        @xml << e
      end
    end
    
    def value
      @xml
    end
  end

  class JSONWrapper < Common
    def initialize(changeset_cache = {}, user_display_name_cache = {})
      super(changeset_cache, user_display_name_cache)
      @json = Hash.new
    end

    def []=(k, v)
      @json[k.to_s] = v
    end

    def tags=(hash_tags)
      @json['tags'] = hash_tags
    end

    def nds(raw_nds, visible_nodes = nil)
      @json['nds'] = Common.ordered_nodes(raw_nds, visible_nodes)
    end

    def members=(raw_members)
      @json['members'] = raw_members.map do |m|
        {'type' => m.member_type.downcase,' ref' => m.member_id, 'role' => m.member_role}
      end
    end

    def value
      @json
    end
  end

  def self.get_wrapper(format, name, changeset_cache = {}, user_display_name_cache = {})
    case format
    when Mime::JSON
      JSONWrapper.new(changeset_cache, user_display_name_cache)
    else
      XMLWrapper.new(name, changeset_cache, user_display_name_cache)
    end
  end

  def self.node(format, node_id, node_obj, changeset_cache = {}, user_display_name_cache = {})
    elt = OSM::Format.get_wrapper(format, 'node', changeset_cache, user_display_name_cache)
    elt.common_attributes(node_id, node_obj)
    if node_obj.visible?
      elt['lat'] = node_obj.lat.to_f
      elt['lon'] = node_obj.lon.to_f
    end
    elt.tags = node_obj.tags
    return elt.value
  end

  def self.way(format, way_id, way_obj, visible_nodes = nil, changeset_cache = {}, user_display_name_cache = {})
    elt = OSM::Format.get_wrapper(format, 'way', changeset_cache, user_display_name_cache)
    elt.common_attributes(way_id, way_obj)
    elt.nds(way_obj.way_nodes, visible_nodes)
    elt.tags = way_obj.tags
    return elt.value
  end

  def self.relation(format, rel_id, rel_obj, changeset_cache = {}, user_display_name_cache = {})
    elt = OSM::Format.get_wrapper(format, 'relation', changeset_cache, user_display_name_cache)
    elt.common_attributes(rel_id, rel_obj)
    elt.members = rel_obj.relation_members
    elt.tags = rel_obj.tags
    return elt.value
  end

  class Document
    def initialize(request, changeset_cache = {}, user_display_name_cache = {})
      if request.negotiate_mime([Mime::JSON]) == Mime::JSON
        @format = Mime::JSON
      else
        @format = Mime::XML
      end

      @changeset_cache = changeset_cache
      @user_display_name_cache = user_display_name_cache

      @nodes = Array.new
      @ways = Array.new
      @relations = Array.new
      @changesets = Array.new
      @bounds = nil
    end

    def mime
      return @format
    end

    def render
      case @format
      when Mime::JSON
        doc = get_json_doc
        doc['nodes'] = @nodes.map do |n| 
          id = n.respond_to?(:node_id) ? n.node_id : n.id
          OSM::Format.node(Mime::JSON, id, n, @changeset_cache, @user_display_name_cache)
        end
        doc['ways'] = @ways.map do |w| 
          id = w.respond_to?(:way_id) ? w.way_id : w.id
          OSM::Format.way(Mime::JSON, id, w, nil, @changeset_cache, @user_display_name_cache)
        end
        doc['relations'] = @relations.map do |r| 
          id = r.respond_to?(:relation_id) ? r.relation_id : r.id
          OSM::Format.relation(Mime::JSON, id, r, @changeset_cache, @user_display_name_cache)
        end
        doc.to_json

      when Mime::XML
        doc = get_xml_doc
        @nodes.each do |n|
          id = n.respond_to?(:node_id) ? n.node_id : n.id
          doc.root << OSM::Format.node(Mime::XML, id, n, @changeset_cache, @user_display_name_cache)
        end
        @ways.each do |w|
          id = w.respond_to?(:way_id) ? w.way_id : w.id
          doc.root << OSM::Format.way(Mime::XML, id, w, nil, @changeset_cache, @user_display_name_cache)
        end
        @relations.each do |r|
          id = r.respond_to?(:relation_id) ? r.relation_id : r.id
          doc.root << OSM::Format.relation(Mime::XML, id, r, @changeset_cache, @user_display_name_cache)
        end
        return doc.to_s

      else
        raise RuntimeError.new("Unknown format #{format.inspect} in document render.")
      end
    end

    def bounds(bbox)
      @bounds = bbox
    end

    def <<(element)
      case element
      when Node, OldNode
        @nodes << element
      when Way, OldWay
        @ways << element
      when Relation, OldRelation
        @relations << element
      when Changeset
        @changesets << element
      else
        if element.respond_to?(:each)
          element.each {|e| self << e }
        else
          raise RuntimeError.new("Unknown element type #{element.class} being added to document.")
        end
      end
    end

    private
    def get_xml_doc
      doc = XML::Document.new
      doc.encoding = XML::Encoding::UTF_8
      root = XML::Node.new 'osm'
      set_hashlike_attributes(root)
      doc.root = root
      return doc
    end

    def get_json_doc
      doc = Hash.new
      # the ruby Hash documentation says "Hashes enumerate their values
      # in the order that the corresponding keys were inserted." this
      # works in our favour here, as we want to ensure that JSON docs
      # have the "header" fields before the content fields. since
      # to_json appears to preserve enumeration order, we just have to
      # make sure the "header" fields are inserted first, even if they
      # get changed later.
      set_hashlike_attributes(doc)
      # we always want nodes, ways & relations elements, even if they
      # are empty, so set them here and have them overridden by later
      # methods.
      ['nodes', 'ways', 'relations'].each {|k| doc[k] = []}
      return doc
    end

    def set_hashlike_attributes(root)
      root['version'] = API_VERSION.to_s
      root['generator'] = GENERATOR
      root['copyright'] = COPYRIGHT_OWNER
      root['attribution'] = ATTRIBUTION_URL
      root['license'] =  LICENSE_URL
    end
  end
end
