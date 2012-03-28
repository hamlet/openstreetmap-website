class OldWay < ActiveRecord::Base
  include ConsistencyValidations
  include Redactable

  self.table_name = "ways"
  self.primary_keys = "way_id", "version"

  belongs_to :changeset
  belongs_to :redaction
  belongs_to :current_way, :class_name => "Way", :foreign_key => "way_id"

  has_many :old_nodes, :class_name => 'OldWayNode', :foreign_key => [:way_id, :version]
  has_many :old_tags, :class_name => 'OldWayTag', :foreign_key => [:way_id, :version]

  validates_associated :changeset
  
  def self.from_way(way)
    old_way = OldWay.new
    old_way.visible = way.visible
    old_way.changeset_id = way.changeset_id
    old_way.timestamp = way.timestamp
    old_way.way_id = way.id
    old_way.version = way.version
    old_way.nds = way.nds
    old_way.tags = way.tags
    return old_way
  end

  def save_with_dependencies!

    # dont touch this unless you really have figured out why it's called
    # (Rails doesn't deal well with the old ways table (called 'ways') because
    # it doesn't have a unique key. It knows how to insert and auto_increment
    # id and get it back but we have that and we want to get the 'version' back
    # we could add another column but thats a lot of data. No, set_primary_key
    # doesn't work either.
    save!
    clear_aggregation_cache
    clear_association_cache
    @attributes.update(OldWay.where(:way_id => self.way_id, :timestamp => self.timestamp).order("version DESC").first.instance_variable_get('@attributes'))

    # ok, you can touch from here on

    self.tags.each do |k,v|
      tag = OldWayTag.new
      tag.k = k
      tag.v = v
      tag.way_id = self.way_id
      tag.version = self.version
      tag.save!
    end

    sequence = 1
    self.nds.each do |n|
      nd = OldWayNode.new
      nd.id = [self.way_id, self.version, sequence]
      nd.node_id = n
      nd.save!
      sequence += 1
    end
  end

  def nds
    unless @nds
      @nds = Array.new
      OldWayNode.where(:way_id => self.way_id, :version => self.version).order(:sequence_id).each do |nd|
        @nds += [nd.node_id]
      end
    end
    @nds
  end

  def tags
    unless @tags
      @tags = Hash.new
      OldWayTag.where(:way_id => self.way_id, :version => self.version).each do |tag|
        @tags[tag.k] = tag.v
      end
    end
    @tags = Hash.new unless @tags
    @tags
  end

  def nds=(s)
    @nds = s
  end

  def tags=(t)
    @tags = t
  end

  def to_xml_node
    el1 = XML::Node.new 'way'
    el1['id'] = self.way_id.to_s
    el1['visible'] = self.visible.to_s
    el1['timestamp'] = self.timestamp.xmlschema
    if self.changeset.user.data_public?
      el1['user'] = self.changeset.user.display_name
      el1['uid'] = self.changeset.user.id.to_s
    end
    el1['version'] = self.version.to_s
    el1['changeset'] = self.changeset.id.to_s

    if self.redacted?
      el1['redacted'] = self.redaction.title
    end
    
    unless self.redacted? and (@user.nil? or not @user.moderator?)
      # If a way is redacted and the user isn't a moderator, only show
      # meta-data from this revision, but no real data.
      self.old_nodes.each do |nd| # FIXME need to make sure they come back in the right order
        e = XML::Node.new 'nd'
        e['ref'] = nd.node_id.to_s
        el1 << e
      end
      
      self.old_tags.each do |tag|
        e = XML::Node.new 'tag'
        e['k'] = tag.k
        e['v'] = tag.v
        el1 << e
      end
    end
    return el1
  end

  # Read full version of old way
  # For get_nodes_undelete, uses same nodes, even if they've moved since
  # For get_nodes_revert,   allocates new ids 
  # Currently returns Potlatch-style array
  # where [5] indicates whether latest version is usable as is (boolean)
  # (i.e. is it visible? are we actually reverting to an earlier version?)

  def get_nodes_undelete
    points = []
    self.nds.each do |n|
      node = Node.find(n)
      points << [node.lon, node.lat, n, node.version, node.tags_as_hash, node.visible]
    end
    points
  end
  
  def get_nodes_revert(timestamp)
    points=[]
    self.nds.each do |n|
      oldnode = OldNode.where('node_id = ? AND timestamp <= ?', n, timestamp).order("timestamp DESC").first
      curnode = Node.find(n)
      id = n; reuse = curnode.visible
      if oldnode.lat != curnode.lat or oldnode.lon != curnode.lon or oldnode.tags != curnode.tags then
        # node has changed: if it's in other ways, give it a new id
        if curnode.ways-[self.way_id] then id=-1; reuse=false end
      end
      points << [oldnode.lon, oldnode.lat, id, curnode.version, oldnode.tags_as_hash, reuse]
    end
    points
  end

  # Temporary method to match interface to nodes
  def tags_as_hash
    return self.tags
  end

  # Temporary method to match interface to ways
  def way_nodes
    return self.old_nodes
  end

  # Pretend we're not in any relations
  def containing_relation_members
    return []
  end

  # check whether this element is the latest version - that is,
  # has the same version as its "current" counterpart.
  def is_latest_version?
    current_way.version == self.version
  end
end
