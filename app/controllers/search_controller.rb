class SearchController < ApplicationController
  # Support searching for nodes, ways, or all
  # Can search by tag k, v, or both (type->k,value->v)
  # Can search by name (k=name,v=....)
  skip_before_filter :verify_authenticity_token
  after_filter :compress_output

  def search_all
    do_search(true,true,true)
  end

  def search_ways
    do_search(true,false,false)
  end
  def search_nodes
    do_search(false,true,false)
  end
  def search_relations
    do_search(false,false,true)
  end

  def do_search(do_ways,do_nodes,do_relations)
    type = params['type']
    value = params['value']
    unless type or value
      name = params['name']
      if name
        type = 'name'
        value = name
      end
    end

    if do_nodes
      response.headers['Error'] = "Searching of nodes is currently unavailable"
      render :text => "", :status => :service_unavailable
      return false
    end

    unless value
      response.headers['Error'] = "Searching for a key without value is currently unavailable"
      render :text => "", :status => :service_unavailable
      return false
    end

    # Matching for node tags table
    if do_nodes
      nodes = Node.joins(:node_tags)
      nodes = nodes.where(:current_node_tags => { :k => type }) if type
      nodes = nodes.where(:current_node_tags => { :v => value }) if value
      nodes = nodes.limit(100)
    else
      nodes = Array.new
    end

    # Matching for way tags table
    if do_ways
      ways = Way.joins(:way_tags)
      ways = ways.where(:current_way_tags => { :k => type }) if type
      ways = ways.where(:current_way_tags => { :v => value }) if value
      ways = ways.limit(100)
    else
      ways = Array.new
    end

    # Matching for relation tags table
    if do_relations
      relations = Relation.joins(:relation_tags)
      relations = relations.where(:current_relation_tags => { :k => type }) if type
      relations = relations.where(:current_relation_tags => { :v => value }) if value
      relations = relations.limit(2000)
    else
      relations = Array.new
    end

    # Fetch any node needed for our ways (only have matching nodes so far)
    nodes += Node.find(ways.collect { |w| w.nds }.uniq)

    # Print
    doc = OSM::Format::Document.new(request)
    nodes.each do |node|
      doc << node
    end

    ways.each do |way|
      doc << way
    end

    relations.each do |rel|
      doc << rel
    end

    render :text => doc.render, :content_type => doc.mime
  end
end
