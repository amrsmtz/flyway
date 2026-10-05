module Agent
  # How old the data behind an answer is, per feed actually used.
  class Freshness
    FEEDS_BY_TOOL = {
      "night_weather" => %w[open_meteo inaturalist],
      "migration_activity" => %w[inaturalist ebird], "species_changes" => %w[inaturalist ebird],
      "source_comparison" => %w[inaturalist ebird], "observation_coverage" => %w[inaturalist ebird]
    }.freeze

    def initialize(tools_used)
      @feeds = tools_used.flat_map { |tool| FEEDS_BY_TOOL.fetch(tool, []) }.uniq
    end

    def to_a
      @feeds.map do |feed|
        status = FeedStatus.for(feed)
        { feed: feed, name: status.name, health: status.health.to_s,
          collected_at: status.last_success_at&.iso8601, newest_data_at: status.latest_data_at&.iso8601 }
      end
    end
  end
end
