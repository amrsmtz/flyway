module Analytics
  module Tools
    # Which species each source reports in a place and period, and where
    # they differ. Disagreement is expected and is not an error by itself:
    # eBird lists every species seen or heard on an outing, while
    # iNaturalist mostly holds birds someone managed to photograph.
    class SourceAgreement < Base
      LIMIT = 10
      WHY = "eBird checklists include every species seen or heard; iNaturalist mostly holds photographed birds, " \
            "so small, fast, distant or night-calling species are under-represented there.".freeze

      def initialize(place:, period:)
        super()
        @area = Area.new(place)
        @period = period
      end

      def call
        ebird = species_records("ebird")
        inaturalist = species_records("inaturalist")
        shared = ebird.keys & inaturalist.keys
        union = ebird.keys | inaturalist.keys
        add_flags(ebird, inaturalist)
        add_evidence(inaturalist.keys - ebird.keys)

        result(
          place: @area.name, period: @period.as_json,
          species: { ebird: ebird.size, inaturalist: inaturalist.size, both: shared.size,
                     only_on_ebird: ebird.size - shared.size, only_on_inaturalist: inaturalist.size - shared.size,
                     display: share_display(shared.size, union.size, "species reported by either source are reported by both") },
          only_on_ebird: describe(ebird.except(*inaturalist.keys)),
          only_on_inaturalist: describe(inaturalist.except(*ebird.keys)),
          effort: { ebird_checklists_reported: ebird_checklists, inaturalist_bird_records: inaturalist.values.sum(&:first) },
          why_sources_differ: WHY, notes: @area.notes
        )
      end

      private

      # species_id => [records, records not flagged by the source]
      def species_records(source)
        @period.apply(@area.observations(source)).where.not(species_id: nil).group(:species_id)
               .pluck(:species_id, Arel.sql("count(*)"), Arel.sql("count(*) FILTER (WHERE quality_tier <> 'flagged')"))
               .to_h { |species_id, records, sound| [ species_id, [ records, sound ] ] }
      end

      def describe(records)
        names = Taxon.where(id: records.keys).pluck(:id, :common_name).to_h

        records.sort_by { |_, (count, _)| -count }.first(LIMIT).map do |species_id, (count, sound)|
          entry = { species: names[species_id], records: count }
          entry[:all_awaiting_review] = true if sound.zero?
          entry
        end
      end

      def ebird_checklists
        RegionDayEffort.where(source: "ebird", county_code: @area.effort_county_codes,
                              day: @period.first_day..@period.last_day).sum(:checklist_count)
      end

      def add_flags(ebird, inaturalist)
        flag_if_recent(@period)
        flag("ebird_not_collected", "No eBird data is held for this place and period, so the sources cannot be compared.") if ebird.empty?
        if inaturalist.values.sum(&:first) < INATURALIST_TIERS[:low]
          flag("few_inaturalist_records", "Fewer than #{INATURALIST_TIERS[:low]} iNaturalist bird records: most differences come from that alone.")
        end
      end

      def add_evidence(inaturalist_only)
        scope = @period.apply(@area.observations("inaturalist")).where(species_id: inaturalist_only)
        evidence(
          title: "iNaturalist records of species eBird does not report, #{@area.name}, #{@period}",
          method: "Species lists of both sources for #{@area.name} over #{@period}, compared after mapping both to the eBird taxonomy.",
          source: "iNaturalist", records: inaturalist_records(scope)
        )
      end
    end
  end
end
