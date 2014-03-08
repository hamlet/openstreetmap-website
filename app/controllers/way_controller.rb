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
      render_ways [way]
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
      # create the results document
      doc = OSM::Format::Document.new(request)
      way.nodes.uniq.each do |node|
        if node.visible
          doc << node
        end
      end
      doc << way
      
      render :text => doc.render, :content_type => doc.mime
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

  def render_ways(ways)
    doc = OSM::Format::Document.new(request)
    ways.each do |way|
      doc << way
    end
    render :text => doc.render, :content_type => doc.mime
  end
end
