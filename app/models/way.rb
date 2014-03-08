class Way < ActiveRecord::Base
  require 'xml/libxml'
  
  include ConsistencyValidations
  include NotRedactable
  include ObjectMetadata

  self.table_name = "current_ways"
  
  belongs_to :changeset

  has_many :old_ways, -> { order(:version) }

  has_many :way_nodes, -> { order(:sequence_id) }
  has_many :nodes, -> { order("sequence_id") }, :through => :way_nodes

  has_many :way_tags

  has_many :containing_relation_members, :class_name => "RelationMember", :as => :member
  has_many :containing_relations, :class_name => "Relation", :through => :containing_relation_members, :source => :relation

  validates_presence_of :id, :on => :update
  validates_presence_of :changeset_id,:version,  :timestamp
  validates_uniqueness_of :id
  validates_inclusion_of :visible, :in => [ true, false ]
  validates_numericality_of :changeset_id, :version, :integer_only => true
  validates_numericality_of :id, :on => :update, :integer_only => true
  validates_associated :changeset

  scope :visible, -> { where(:visible => true) }
  scope :invisible, -> { where(:visible => false) }

  def self.from_format(format, data, create=false)
    case format
    when Mime::XML, nil
      self.from_xml(data, create)
    when Mime::JSON
      self.from_json(data, create)
    else
      raise OSM::APINotAcceptable.new("way", format)
    end
  end

  # Read in xml as text and return it's Way object representation
  def self.from_xml(xml, create=false)
    begin
      p = XML::Parser.string(xml)
      doc = p.parse

      doc.find('//osm/way').each do |pt|
        return Way.from_xml_node(pt, create)
      end
      raise OSM::APIBadXMLError.new("node", xml, "XML doesn't contain an osm/way element.")
    rescue LibXML::XML::Error, ArgumentError => ex
      raise OSM::APIBadXMLError.new("way", xml, ex.message)
    end
  end

  # parse a JSON doc and extract the way from it
  def self.from_json(json, create=false)
    begin
      doc = JSON.parse(json)

      raise OSM::APIBadXMLError.new("way", json, "JSON must be an object.") unless doc.instance_of?(Hash)
      raise OSM::APIBadXMLError.new("way", json, "JSON must contain a 'ways' key.") unless doc.has_key?('ways')

      ways = doc['ways']
      if ways.instance_of?(Hash)
        return Way.from_json_node(ways, create)
      elsif ways.instance_of?(Array) and ways.length > 0
        return Way.from_json_node(ways[0], create)
      else
        raise OSM::APIBadXMLError.new("way", json, "JSON 'ways' entry must be either an array or an object.")
      end

    rescue JSON::ParserError => ex
      raise OSM::APIBadXMLError.new("way", json, ex.message)
    end
  end

  ##
  # generate a way from a hash-like structure, i.e: duck-typed on string
  # lookup attributes with operator[].
  def self.from_hashlike_node(pt, create=false, &error)
    way = Way.new

    error.call("way", pt, "Version is required when updating") unless create or not pt['version'].nil?
    way.version = pt['version']
    error.call("way", pt, "Changeset id is missing") if pt['changeset'].nil?
    way.changeset_id = pt['changeset']

    unless create
      error.call("way", pt, "ID is required when updating") if pt['id'].nil?
      way.id = pt['id'].to_i
      # .to_i will return 0 if there is no number that can be parsed. 
      # We want to make sure that there is no id with zero anyway
      raise OSM::APIBadUserInput.new("ID of way cannot be zero when updating.") if way.id == 0
    end

    # We don't care about the timestamp nor the visibility as these are either
    # set explicitly or implicit in the action. The visibility is set to true, 
    # and manually set to false before the actual delete.
    way.visible = true

    # Start with no tags
    way.tags = Hash.new

    return way
  end

  def self.from_xml_node(pt, create=false)
    way = Way.from_hashlike_node(pt, create) {|typ, err_pt, msg| raise OSM::APIBadXMLError.new(typ, err_pt, msg) }

    # Add in any tags from the XML
    pt.find('tag').each do |tag|
      raise OSM::APIBadXMLError.new("way", pt, "tag is missing key") if tag['k'].nil?
      raise OSM::APIBadXMLError.new("way", pt, "tag is missing value") if tag['v'].nil?
      way.add_tag_keyval(tag['k'], tag['v'])
    end

    pt.find('nd').each do |nd|
      way.add_nd_num(nd['ref'])
    end

    return way
  end

  # parse a way from a hash object
  def self.from_json_node(doc, create)
    raise OSM::APIBadXMLError.new("way", doc.to_json, "is not an object.") unless doc.instance_of? Hash
    way = Way.from_hashlike_node(doc, create) {|typ, err_doc, msg| raise OSM::APIBadXMLError.new(typ, err_doc.to_json, msg) }
    
    if doc.has_key? 'tags'
      doc_tags = doc['tags']
      raise OSM::APIBadXMLError.new("way", doc_tags.to_json, "way/tags is not an object") unless doc_tags.instance_of? Hash
      doc_tags.each do |k, v|
        way.add_tag_keyval(k, v)
      end
    end

    if doc.has_key? 'nds'
      doc_nds = doc['nds']
      raise OSM::APIBadXMLError.new("way", doc_nds.to_json, "way/nds is not an array") unless doc_nds.instance_of? Array
      doc_nds.each do |nd|
        way.add_nd_num(nd.to_i)
      end
    end

    return way
  end

  # Find a way given it's ID, and in a single SQL call also grab its nodes
  #
  # You can't pull in all the tags too unless we put a sequence_id on the way_tags table and have a multipart key
  def self.find_eager(id)
    way = Way.find(id, :include => {:way_nodes => :node})
    #If waytag had a multipart key that was real, you could do this:
    #way = Way.find(id, :include => [:way_tags, {:way_nodes => :node}])
  end

  def to_format(format)
    case format
    when Mime::JSON
      to_osmjson
    else
      to_xml
    end
  end

  # Find a way given it's ID, and in a single SQL call also grab its nodes and tags
  def to_xml
    doc = OSM::API.new.get_xml_doc
    doc.root << to_xml_node()
    return doc
  end

  def to_xml_node(visible_nodes = nil, changeset_cache = {}, user_display_name_cache = {})
    OSM::Format.way(Mime::XML, id, self, visible_nodes, changeset_cache, user_display_name_cache)
  end 

  def to_osmjson
    doc = OSM::API.new.get_json_doc
    doc['ways'] = [to_osmjson_node()]
    return doc.to_json
  end

  def to_osmjson_node(visible_nodes = nil, changeset_cache = {}, user_display_name_cache = {})
    OSM::Format.way(Mime::JSON, id, self, visible_nodes, changeset_cache, user_display_name_cache)
  end 

  def nds
    @nds ||= self.way_nodes.collect { |n| n.node_id }
  end

  def tags
    @tags ||= Hash[self.way_tags.collect { |t| [t.k, t.v] }]
  end

  def nds=(s)
    @nds = s
  end

  def tags=(t)
    @tags = t
  end

  def add_nd_num(n)
    @nds = Array.new unless @nds
    @nds << n.to_i
  end

  def add_tag_keyval(k, v)
    @tags = Hash.new unless @tags

    # duplicate tags are now forbidden, so we can't allow values
    # in the hash to be overwritten.
    raise OSM::APIDuplicateTagsError.new("way", self.id, k) if @tags.include? k

    @tags[k] = v
  end

  ##
  # the integer coords (i.e: unscaled) bounding box of the way, assuming
  # straight line segments.
  def bbox
    lons = nodes.collect { |n| n.longitude }
    lats = nodes.collect { |n| n.latitude }
    BoundingBox.new(lons.min, lats.min, lons.max, lats.max)
  end

  def update_from(new_way, user)
    Way.transaction do
      self.lock!
      check_consistency(self, new_way, user)
      unless new_way.preconditions_ok?(self.nds)
        raise OSM::APIPreconditionFailedError.new("Cannot update way #{self.id}: data is invalid.")
      end
      
      self.changeset_id = new_way.changeset_id
      self.changeset = new_way.changeset
      self.tags = new_way.tags
      self.nds = new_way.nds
      self.visible = true
      save_with_history!
    end
  end

  def create_with_history(user)
    check_create_consistency(self, user)
    unless self.preconditions_ok?
      raise OSM::APIPreconditionFailedError.new("Cannot create way: data is invalid.")
    end
    self.version = 0
    self.visible = true
    save_with_history!
  end

  def preconditions_ok?(old_nodes = [])
    return false if self.nds.empty?
    if self.nds.length > MAX_NUMBER_OF_WAY_NODES
      raise OSM::APITooManyWayNodesError.new(self.id, self.nds.length, MAX_NUMBER_OF_WAY_NODES)
    end

    # check only the new nodes, for efficiency - old nodes having been checked last time and can't
    # be deleted when they're in-use.
    new_nds = (self.nds - old_nodes).sort.uniq

    unless new_nds.empty?
      db_nds = Node.where(:id => new_nds, :visible => true)

      if db_nds.length < new_nds.length
        missing = new_nds - db_nds.collect { |n| n.id }
        raise OSM::APIPreconditionFailedError.new("Way #{self.id} requires the nodes with id in (#{missing.join(',')}), which either do not exist, or are not visible.")
      end
    end

    return true
  end

  def delete_with_history!(new_way, user)
    unless self.visible
      raise OSM::APIAlreadyDeletedError.new("way", new_way.id)
    end
    
    # need to start the transaction here, so that the database can 
    # provide repeatable reads for the used-by checks. this means it
    # shouldn't be possible to get race conditions.
    Way.transaction do
      self.lock!
      check_consistency(self, new_way, user)
      rels = Relation.joins(:relation_members).where(:visible => true, :current_relation_members => { :member_type => "Way", :member_id => id }).order(:id)
      raise OSM::APIPreconditionFailedError.new("Way #{self.id} is still used by relations #{rels.collect { |r| r.id }.join(",")}.") unless rels.empty?

      self.changeset_id = new_way.changeset_id
      self.changeset = new_way.changeset

      self.tags = []
      self.nds = []
      self.visible = false
      save_with_history!
    end
  end

  # Temporary method to match interface to nodes
  def tags_as_hash
    return self.tags
  end

  ##
  # if any referenced nodes are placeholder IDs (i.e: are negative) then
  # this calling this method will fix them using the map from placeholders 
  # to IDs +id_map+. 
  def fix_placeholders!(id_map, placeholder_id = nil)
    self.nds.map! do |node_id|
      if node_id < 0
        new_id = id_map[:node][node_id]
        raise OSM::APIBadUserInput.new("Placeholder node not found for reference #{node_id} in way #{self.id.nil? ? placeholder_id : self.id}") if new_id.nil?
        new_id
      else
        node_id
      end
    end
  end

  private
  
  def save_with_history!
    t = Time.now.getutc

    # update the bounding box, note that this has to be done both before 
    # and after the save, so that nodes from both versions are included in the 
    # bbox. we use a copy of the changeset so that it isn't reloaded
    # later in the save.
    cs = self.changeset
    cs.update_bbox!(bbox) unless nodes.empty?

    Way.transaction do
      self.version += 1
      self.timestamp = t
      self.save!

      tags = self.tags
      WayTag.delete_all(:way_id => self.id)
      tags.each do |k,v|
        tag = WayTag.new
        tag.way_id = self.id
        tag.k = k
        tag.v = v
        tag.save!
      end

      nds = self.nds
      WayNode.delete_all(:way_id => self.id)
      sequence = 1
      nds.each do |n|
        nd = WayNode.new
        nd.id = [self.id, sequence]
        nd.node_id = n
        nd.save!
        sequence += 1
      end

      old_way = OldWay.from_way(self)
      old_way.timestamp = t
      old_way.save_with_dependencies!

      # reload the way so that the nodes array points to the correct
      # new set of nodes.
      self.reload

      # update and commit the bounding box, now that way nodes 
      # have been updated and we're in a transaction.
      cs.update_bbox!(bbox) unless nodes.empty?

      # tell the changeset we updated one element only
      cs.add_changes! 1

      cs.save!
    end
  end
end
