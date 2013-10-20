class WayController < ApplicationController
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

    way = Way.from_format(request.content_mime_type, request.raw_post, true)
    
    if way
      way.create_with_history @user
      render :text => way.id.to_s, :content_type => "text/plain"
    else
      render :text => "", :status => :bad_request
    end
  end

  def read
    way = Way.find(params[:id])
    
    response.last_modified = way.timestamp
    
    if way.visible
      render_way way
    else
      render :text => "", :status => :gone
    end
  end

  def update
    way = Way.find(params[:id])
    new_way = Way.from_format(request.content_mime_type, request.raw_post)
    
    if new_way and new_way.id == way.id
      way.update_from(new_way, @user)
      render :text => way.version.to_s, :content_type => "text/plain"
    else
      render :text => "", :status => :bad_request
    end
  end

  # This is the API call to delete a way
  def delete
    way = Way.find(params[:id])
    new_way = Way.from_format(request.content_mime_type, request.raw_post)
    
    if new_way and new_way.id == way.id
      way.delete_with_history!(new_way, @user)
      render :text => way.version.to_s, :content_type => "text/plain"
    else
      render :text => "", :status => :bad_request
    end
  end

  def full
    way = Way.includes(:nodes => :node_tags).find(params[:id])
    
    if way.visible
      visible_nodes = {}
      changeset_cache = {}
      user_display_name_cache = {}

      doc = OSM::API.new.get_xml_doc
      way.nodes.uniq.each do |node|
        if node.visible
          doc.root << node.to_xml_node(changeset_cache, user_display_name_cache)
          visible_nodes[node.id] = node
        end
      end
      doc.root << way.to_xml_node(visible_nodes, changeset_cache, user_display_name_cache)
      
      render :text => doc.to_s, :content_type => "text/xml"
    else
      render :text => "", :status => :gone
    end
  end

  def ways
    if not params['ways']
      raise OSM::APIBadUserInput.new("The parameter ways is required, and must be of the form ways=id[,id[,id...]]")
    end

    ids = params['ways'].split(',').collect { |w| w.to_i }

    if ids.length == 0
      raise OSM::APIBadUserInput.new("No ways were given to search for")
    end

    doc = OSM::API.new.get_xml_doc

    render_ways Way.find(ids)
  end

  ##
  # returns all the ways which are currently using the node given in the 
  # :id parameter. note that this used to return deleted ways as well, but
  # this seemed not to be the expected behaviour, so it was removed.
  def ways_for_node
    wayids = WayNode.where(:node_id => params[:id]).collect { |ws| ws.id[0] }.uniq
    render_ways(Way.find(wayids).select {|w| w.visible})
  end

private

  def render_way(way)
    format = request.negotiate_mime([Mime::JSON]) or Mime::XML
    render :text => way.to_format(format).to_s, :content_type => format
  end

  def render_ways(ways)
    if request.negotiate_mime([Mime::JSON]) == Mime::JSON
      doc = OSM::API.new.get_json_doc
      doc['ways'] = ways.map {|way| way.to_osmjson_node}
      render :text => doc.to_json, :content_type => Mime::JSON

    else
      doc = OSM::API.new.get_xml_doc
      ways.each do |way|
        doc.root << way.to_xml_node
      end
      render :text => doc.to_s, :content_type => "text/xml"
    end
  end
end
