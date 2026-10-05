module Analytics
  module Tools
    # Species reported in one period and not in another: arrivals and
    # departures. A species counts as present in a period when it has at
    # least one confirmed record or two records of any quality, so a single
    # unreviewed sighting does not create an "arrival".
    class SpeciesTurnover < Base
      SOURCES = %w[inaturalist ebird].freeze
      LIMIT = 12

      def initialize(place:, period:, earlier: nil)
        super()
        @area = Area.new(place)
        @period = period
        @earlier = earlier || period.previous
      end

      def call
        now = presence(@period)
        before = presence(@earlier)
        arrivals = describe(now.keys - before.keys, now)
        departures = describe(before.keys - now.keys, before)
        effort = { later: effort(@period), earlier: effort(@earlier) }
        add_flags(effort)
        add_evidence(arrivals)

        result(
          place: @area.name, later_period: @period.as_json, earlier_period: @earlier.as_json,
          species_in_both: (now.keys & before.keys).size,
          arrivals: arrivals.first(LIMIT), arrival_count: arrivals.size,
          departures: departures.first(LIMIT), departure_count: departures.size,
          effort: effort, notes: @area.notes
        )
      end

      private

      # species_id => { source => [records, confirmed records] } for species
      # that pass the presence rule.
      def presence(period)
        rows = SOURCES.flat_map do |source|
          period.apply(@area.observations(source)).where.not(species_id: nil).group(:species_id)
                .pluck(:species_id, Arel.sql("count(*)"), Arel.sql("count(*) FILTER (WHERE quality_tier = 'confirmed')"))
                .map { |species_id, records, confirmed| [ species_id, source, records, confirmed ] }
        end

        by_species = rows.group_by(&:first).transform_values do |entries|
          entries.to_h { |_, source, records, confirmed| [ source, [ records, confirmed ] ] }
        end
        by_species.select { |_, sources| sources.values.sum(&:last).positive? || sources.values.sum(&:first) >= 2 }
      end

      def describe(species_ids, presence)
        taxa = Taxon.where(id: species_ids).includes(:species_group).index_by(&:id)

        species_ids.map do |id|
          sources = presence.fetch(id)
          { species: taxa[id].common_name, group: taxa[id].species_group&.name,
            records: sources.transform_values(&:first), confirmed_records: sources.values.sum(&:last) }.compact
        end.sort_by { |entry| -entry[:records].values.sum }
      end

      def effort(period)
        { inaturalist_bird_records: period.apply(@area.observations("inaturalist")).count,
          ebird_checklists_reported: RegionDayEffort.where(source: "ebird", county_code: @area.effort_county_codes,
                                                           day: period.first_day..period.last_day).sum(:checklist_count) }
      end

      # More effort finds more species, so unequal effort alone can produce
      # "arrivals".
      def add_flags(effort)
        flag_if_recent(@period)
        later = effort[:later][:inaturalist_bird_records]
        earlier = effort[:earlier][:inaturalist_bird_records]
        if [ later, earlier ].min < INATURALIST_TIERS[:low]
          flag("few_inaturalist_records", "One of the periods has fewer than #{INATURALIST_TIERS[:low]} iNaturalist bird records.")
        elsif later > earlier * 1.5 || earlier > later * 1.5
          flag("unequal_effort", "Observer effort differs between the periods (#{earlier} then #{later} iNaturalist bird records), " \
                                 "which by itself changes how many species are found.")
        end
      end

      def add_evidence(arrivals)
        names = arrivals.first(LIMIT).pluck(:species)
        scope = @period.apply(@area.observations("inaturalist")).joins(:species).where(taxa: { common_name: names })
        evidence(
          title: "Records of species newly reported in #{@area.name}, #{@period}",
          method: "Species with at least one confirmed record or two records in #{@period}, and none meeting that rule in #{@earlier}. " \
                  "Both iNaturalist and eBird are used.",
          source: "iNaturalist and eBird", records: inaturalist_records(scope)
        )
      end
    end
  end
end
