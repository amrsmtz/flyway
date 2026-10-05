# Operational view of the three feeds: freshness, queue progress, failures
# and what the data holds. Everything here is also what lowers the agent's
# confidence, shown in the open.
class StatusController < ApplicationController
  COVERAGE_DAYS = 7

  def show
    @feeds = FeedStatus::FEEDS.map { |feed| FeedStatus.for(feed) }
    @queues = IngestionUnit.group(:feed, :kind, :status).count
    @dead_units = IngestionUnit.dead.order(finished_at: :desc).limit(10)
    @observations = Observation.group(:source, :quality_tier).count
    @observation_range = Observation.group(:source).pluck(:source, Arel.sql("min(observed_on)"), Arel.sql("max(observed_on)"))
    @checklists = Checklist.count
    @weather_hours = WeatherHour.count
    @weather_range = [ WeatherHour.minimum(:time), WeatherHour.where(forecast: false).maximum(:time) ]
    @unmatched_taxa = TaxonCrosswalk.unmatched.order(:source_name).limit(40)
    @unmatched_records = Observation.where(source: "inaturalist", taxon_id: nil).count
    @coverage = ebird_coverage
  end

  private

  # Days of the 12-month window for which eBird's effort figures are held,
  # per county.
  def ebird_coverage
    days = RegionDayEffort.where(source: "ebird").group(:county_code).count
    names = Place.counties.where(ebird_code: days.keys).pluck(:ebird_code, :name).to_h
    days.map { |code, count| [ names[code] || code, count ] }.sort_by { |name, _| name }
  end
end
