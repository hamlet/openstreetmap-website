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
end
