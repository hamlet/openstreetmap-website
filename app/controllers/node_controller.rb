# The NodeController is the RESTful interface to Node objects

class NodeController < ApplicationController
  require 'xml/libxml'

  skip_before_filter :verify_authenticity_token
  before_filter :authorize, :only => [:create, :update, :delete]
  before_filter :require_allow_write_api, :only => [:create, :update, :delete]
  before_filter :require_public_data, :only => [:create, :update, :delete]
  before_filter :check_api_writable, :only => [:create, :update, :delete]
  before_filter :check_api_readable, :except => [:create, :update, :delete]
  after_filter :compress_output
  around_filter :api_call_handle_error, :api_call_timeout

  # Create a node from XML.
  def create
    assert_method :put

    node = Node.from_format(request.content_mime_type, request.raw_post, true)

    # Assume that Node.from_format has thrown an exception if there is an error parsing the xml
    node.create_with_history @user
    render :text => node.id.to_s, :content_type => "text/plain"
  end

  # Dump the details on a node given in params[:id]
  def read
    node = Node.find(params[:id])

    response.last_modified = node.timestamp

    if node.visible
      render_nodes [node]
    else
      render :text => "", :status => :gone
    end
  end
  
  # Update a node from given XML
  def update
    node = Node.find(params[:id])
    new_node = Node.from_format(request.content_mime_type, request.raw_post)
       
    unless new_node and new_node.id == node.id
      raise OSM::APIBadUserInput.new("The id in the url (#{node.id}) is not the same as provided in the xml (#{new_node.id})")
    end
    node.update_from(new_node, @user)
    render :text => node.version.to_s, :content_type => "text/plain"
  end

  # Delete a node. Doesn't actually delete it, but retains its history 
  # in a wiki-like way. We therefore treat it like an update, so the delete
  # method returns the new version number.
  def delete
    node = Node.find(params[:id])
    new_node = Node.from_format(request.content_mime_type, request.raw_post)
    
    unless new_node and new_node.id == node.id
      raise OSM::APIBadUserInput.new("The id in the url (#{node.id}) is not the same as provided in the xml (#{new_node.id})")
    end
    node.delete_with_history!(new_node, @user)
    render :text => node.version.to_s, :content_type => "text/plain"
  end

  # Dump the details on many nodes whose ids are given in the "nodes" parameter.
  def nodes
    if not params['nodes']
      raise OSM::APIBadUserInput.new("The parameter nodes is required, and must be of the form nodes=id[,id[,id...]]")
    end

    ids = params['nodes'].split(',').collect { |n| n.to_i }

    if ids.length == 0
      raise OSM::APIBadUserInput.new("No nodes were given to search for")
    end

    render_nodes Node.find(ids)
  end

private

  def render_nodes(nodes)
    if request.negotiate_mime([Mime::JSON]) == Mime::JSON
      doc = OSM::API.new.get_json_doc
      doc['nodes'] = nodes.map {|node| node.to_osmjson_node}
      render :text => doc.to_json, :content_type => Mime::JSON

    else
      doc = OSM::API.new.get_xml_doc
      nodes.each do |node|
        doc.root << node.to_xml_node
      end
      render :text => doc.to_s, :content_type => "text/xml"
    end
  end
end
