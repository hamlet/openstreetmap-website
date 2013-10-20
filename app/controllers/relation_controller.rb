class RelationController < ApplicationController
  require 'xml/libxml'

  skip_before_filter :verify_authenticity_token
  before_filter :authorize, :only => [:create, :update, :delete]
  before_filter :require_allow_write_api, :only => [:create, :update, :delete]
  before_filter :require_public_data, :only => [:create, :update, :delete]
  before_filter :check_api_writable, :only => [:create, :update, :delete]
  before_filter :check_api_readable, :except => [:create, :update, :delete]
  after_filter :compress_output
  around_filter :api_call_handle_error, :api_call_timeout

  def create
    assert_method :put

    relation = Relation.from_format(request.content_mime_type, request.raw_post, true)
    
    # We assume that an exception has been thrown if there was an error 
    # generating the relation
    #if relation
    relation.create_with_history @user
    render :text => relation.id.to_s, :content_type => "text/plain"
    #else
    # render :text => "Couldn't get turn the input into a relation.", :status => :bad_request
    #end
  end

  def read
    relation = Relation.find(params[:id])
    response.last_modified = relation.timestamp
    if relation.visible
      render_relation relation

    else
      render :text => "", :status => :gone
    end
  end

  def update
    logger.debug request.raw_post

    relation = Relation.find(params[:id])
    new_relation = Relation.from_format(request.content_mime_type, request.raw_post)
    
    if new_relation and new_relation.id == relation.id
      relation.update_from new_relation, @user
      render :text => relation.version.to_s, :content_type => "text/plain"
    else
      render :text => "", :status => :bad_request
    end
  end

  def delete
    relation = Relation.find(params[:id])
    new_relation = Relation.from_format(request.content_mime_type, request.raw_post)
    if new_relation and new_relation.id == relation.id
      relation.delete_with_history!(new_relation, @user)
      render :text => relation.version.to_s, :content_type => "text/plain"
    else
      render :text => "", :status => :bad_request
    end
  end

  # -----------------------------------------------------------------
  # full
  # 
  # input parameters: id
  #
  # returns XML representation of one relation object plus all its
  # members, plus all nodes part of member ways
  # -----------------------------------------------------------------
  def full
    relation = Relation.find(params[:id])
    
    if relation.visible
      
      # first find the ids of nodes, ways and relations referenced by this
      # relation - note that we exclude this relation just in case.
      
      node_ids = relation.members.select { |m| m[0] == 'Node' }.map { |m| m[1] }
      way_ids = relation.members.select { |m| m[0] == 'Way' }.map { |m| m[1] }
      relation_ids = relation.members.select { |m| m[0] == 'Relation' and m[1] != relation.id }.map { |m| m[1] }
      
      # next load the relations and the ways.
      
      relations = Relation.where(:id => relation_ids).includes(:relation_tags)
      ways = Way.where(:id => way_ids).includes(:way_nodes, :way_tags)
      
      # now additionally collect nodes referenced by ways. Note how we 
      # recursively evaluate ways but NOT relations.
      
      way_node_ids = ways.collect { |way|
        way.way_nodes.collect { |way_node| way_node.node_id }
      }
      node_ids += way_node_ids.flatten
      nodes = Node.where(:id => node_ids.uniq).includes(:node_tags)
      
      # create XML.
      doc = OSM::API.new.get_xml_doc
      visible_nodes = {}
      visible_members = { "Node" => {}, "Way" => {}, "Relation" => {} }
      changeset_cache = {}
      user_display_name_cache = {}
      
      nodes.each do |node|
        if node.visible? # should be unnecessary if data is consistent.
          doc.root << node.to_xml_node(changeset_cache, user_display_name_cache)
          visible_nodes[node.id] = node
          visible_members["Node"][node.id] = true
        end
      end
      ways.each do |way|
        if way.visible? # should be unnecessary if data is consistent.
          doc.root << way.to_xml_node(visible_nodes, changeset_cache, user_display_name_cache)
          visible_members["Way"][way.id] = true
        end
      end
      relations.each do |rel|
        if rel.visible? # should be unnecessary if data is consistent.
          doc.root << rel.to_xml_node(nil, changeset_cache, user_display_name_cache)
          visible_members["Relation"][rel.id] = true
        end
      end
      # finally add self and output
      doc.root << relation.to_xml_node(visible_members, changeset_cache, user_display_name_cache)
      render :text => doc.to_s, :content_type => "text/xml"
      
    else
      render :text => "", :status => :gone
    end
  end

  def relations
    if not params['relations']
      raise OSM::APIBadUserInput.new("The parameter relations is required, and must be of the form relations=id[,id[,id...]]")
    end

    ids = params['relations'].split(',').collect { |w| w.to_i }

    if ids.length == 0
      raise OSM::APIBadUserInput.new("No relations were given to search for")
    end

    render_relations(Relation.find(ids))
  end

  def relations_for_way
    relations_for_object("Way")
  end

  def relations_for_node
    relations_for_object("Node")
  end

  def relations_for_relation
    relations_for_object("Relation")
  end

  def relations_for_object(objtype)
    relationids = RelationMember.where(:member_type => objtype, :member_id => params[:id]).collect { |ws| ws.relation_id }.uniq
    render_relations(Relation.find(relationids).select {|r| r.visible})
  end

private

  def render_relation(relation)
    format = request.negotiate_mime([Mime::JSON]) or Mime::XML
    render :text => relation.to_format(format).to_s, :content_type => format
  end

  def render_relations(relations)
    if request.negotiate_mime([Mime::JSON]) == Mime::JSON
      doc = OSM::API.new.get_json_doc
      doc['relations'] = relations.map {|relation| relation.to_osmjson_node}
      render :text => doc.to_json, :content_type => Mime::JSON

    else
      doc = OSM::API.new.get_xml_doc
      relations.each do |relation|
        doc.root << relation.to_xml_node
      end
      render :text => doc.to_s, :content_type => "text/xml"
    end
  end
end
