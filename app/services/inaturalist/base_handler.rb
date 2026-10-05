module Inaturalist
  class BaseHandler
    FEED = "inaturalist".freeze
    UPDATABLE = %i[observed_on province_code latitude longitude quality_tier obscured positional_accuracy_m
                   taxon_id species_id species_group_id details source_updated_at].freeze

    def initialize(client: Client.new)
      @client = client
      @normalizer = Normalizer.new
      @place_ids = Place::PROVINCES.pluck(:inaturalist_place_id)
    end

    def call(unit)
      perform(unit)
    rescue Client::RateLimited => e
      raise Ingestion::Runner::Paused.new(1.hour.from_now, e.message)
    rescue Client::Unavailable => e
      raise Ingestion::Runner::Retryable, e.message
    end

    private

    # Fetches every page matching the filters, in id order. The last id seen
    # is saved in the unit after each page, so an interrupted unit resumes
    # where it stopped. Yields each page of records.
    def each_page(unit, **filters)
      loop do
        records = @client.bird_observations(place_ids: @place_ids, id_above: unit.scope["id_above"].to_i, **filters)
        break if records.empty?

        yield records
        unit.update!(scope: unit.scope.merge("id_above" => records.last.fetch("id")))
        break if records.size < Client::PAGE_SIZE
      end
    end
  end
end
