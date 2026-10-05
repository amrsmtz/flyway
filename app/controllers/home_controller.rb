class HomeController < ApplicationController
  # Zoom shortcuts: [west, south, east, north]. Quebec and Ontario are cut
  # at their settled south; their full extent is mostly empty of records.
  PROVINCE_VIEWS = [
    { name: "All", bounds: [ -84.5, 41.5, -59.0, 51.5 ] },
    { name: "Quebec", bounds: [ -79.8, 44.9, -61.5, 51.0 ] },
    { name: "Ontario", bounds: [ -84.5, 41.6, -74.3, 47.5 ] },
    { name: "New Brunswick", bounds: [ -69.1, 44.5, -63.7, 48.1 ] },
    { name: "Nova Scotia", bounds: [ -66.5, 43.3, -59.6, 47.1 ] },
    { name: "Prince Edward Island", bounds: [ -64.5, 45.9, -61.9, 47.1 ] }
  ].freeze

  def index
    @groups = SpeciesGroup.order(:id).pluck(:key, :name)
    @sites = Place.sites.order(:name).map do |site|
      { name: site.name, longitude: site.longitude, latitude: site.latitude, description: site.details["description"] }
    end
    @feeds = FeedStatus::FEEDS.map { |feed| FeedStatus.for(feed) }
  end
end
