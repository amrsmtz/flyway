# Data for the map and timeline. Each response covers the whole year, so the
# browser can scrub through it without further requests; the cubes are
# cached for a few minutes because building them reads a year of aggregates.
class MapController < ApplicationController
  CACHE_FOR = 10.minutes

  def activity
    resolution = params[:resolution].to_i
    return head :bad_request unless Analytics::ActivityCube::RESOLUTIONS.include?(resolution)

    render_cached("map/activity/#{resolution}") { Analytics::ActivityCube.new(resolution: resolution).to_json }
  end

  def wind
    render_cached("map/wind") { Analytics::WindCube.new.to_json }
  end

  private

  def render_cached(key, &block)
    expires_in CACHE_FOR, public: true
    render json: Rails.cache.fetch(key, expires_in: CACHE_FOR, &block)
  end
end
