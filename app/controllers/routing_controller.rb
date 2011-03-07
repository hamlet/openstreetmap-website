class RoutingController < ApplicationController
  require 'net/http'
  require 'uri'


  # Render start action
  def start
     render :action => "start"
  end


  # Get a kml route
  # 
  def find_route
    # get status of routing service
    if(ROUTING_STATUS === "maintenance")
      # Routing service is in maintenance status. Routes are not calculated at the moment
      @response = "error:maintenance"
      return
    elsif(ROUTING_STATUS === "enabled")
      # Get inputs from request and create a waypoint array from it
      waypoints = Array.new
      params.each do |key, value|
        if(key.to_s[/^wp(\d+)_lat/])
          if waypoints[($1.to_i)-1].nil?
            waypoints[($1.to_i)-1] = { :lat => value }
          else
            waypoints[($1.to_i)-1][:lat] = value
          end
        elsif(key.to_s[/^wp(\d+)_lon/])
          if waypoints[($1.to_i)-1].nil?
            waypoints[($1.to_i)-1] = { :lon => value }
          else
            waypoints[($1.to_i)-1][:lon] = value
          end
        end
      end
  
      waypoints = validateWaypoints(waypoints)
  
      if(waypoints.length < 2)
        # Giveup if not enough waypoints present
        @response = "error:insufficient_waypoints"
        return
      else    # more than one waypoint present
        #TODO: Split route in several segments
        # during development status: simply delete all but two waypoints
        until (waypoints.length <= 2)
          waypoints.delete_at(waypoints.pop)
        end
  
        @response = route(waypoints)
  
        # Check if route content is not empty
        if(@response =~ /<coordinates><\/coordinates>/)
          @response = "error:no_route_found"
          return
        end
      end
    else
      # Config error in application.yml
      @response = "error:configuration_improperly_formatted" 
      return
    end
      
    #TODO: Respond with kml header
    respond_to do |format|
      format.js
    end
  end


  private

  # Check if all latitude and longitude values are given
  # filter out empty waypoints and not well formed waypoints
  def validateWaypoints(to_validate)
    delete_queue = Array.new
    to_validate.each_with_index do |point_pair, index|
      if(point_pair[:lat].empty? && point_pair[:lon].empty?)
        delete_queue << index
      elsif(point_pair[:lat].empty? || point_pair[:lon].empty?)
        # Waypoint is not well formed: contains not both latitude and longitude value
        delete_queue << index
      elsif(!(point_pair[:lat] =~ /\d+(\.\d+)?/) || !(point_pair[:lon] =~ /\d+(\.\d+)?/))
        # Waypoint has no suitable number format
        delete_queue << index
      end
    end

    # Remove awkward waypoints
    until (delete_queue.empty?)
       to_validate.delete_at(delete_queue.pop)
    end
    delete_queue = nil
    return to_validate
  end


  # Decide which routing backend to use
  # simple example for now: fastest car routes by osrm, all the rest by yours
  def route(waypoints)
    if(params[:means] === "car" && params[:mode] === "fastest")
      @engine = "osrm"
      return osrmRoute(waypoints)
    else
      @engine = "yours"
      return yoursRoute(waypoints)
    end
  end


  # Get a route calculated via Yours routing service
  def yoursRoute(waypoints)
    querystring = "#{YOURS_URL}"

    # Static values
    querystring += "?format=kml"
    querystring += "&flat=" + waypoints[0][:lat]
    querystring += "&flon=" + waypoints[0][:lon]
    querystring += "&tlat=" + waypoints[1][:lat]
    querystring += "&tlon=" + waypoints[1][:lon]

    # Dynamic values
    if(params[:means] === "bicycle")
       querystring += "&v=bicycle"
    elsif(params[:means] === "feet")
       querystring += "&v=foot"
    end

    if(params[:mode] === "fastest")
       querystring += "&fast=1"
    elsif(params[:mode] === "shortest")
       querystring += "&fast=0"
    end

    response = fetch_text(querystring)

    # Omit busy server
    if(response =~ /Server is busy/i)
      return "error:yours_busy"
    end

    return response.gsub(/\s+/, " ")
  end


  # Get a route calculated via OSRM routing server
  def osrmRoute(waypoints)
    querystring = "#{OSRM_URL}"

    querystring += "&" + waypoints[0][:lat]
    querystring += "&" + waypoints[0][:lon]
    querystring += "&" + waypoints[1][:lat]
    querystring += "&" + waypoints[1][:lon]

    return fetch_text(querystring)
  end


  # Execute http request
  def fetch_text(url)
    return Net::HTTP.get(URI.parse(url))
  end
end
