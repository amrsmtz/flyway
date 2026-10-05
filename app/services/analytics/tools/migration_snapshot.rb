module Analytics
  module Tools
    # How much of a species group (or of all birds) is being reported in a
    # place over a period, against a comparison period, normalised by
    # observer effort: a share of bird records for iNaturalist, a share of
    # complete checklists for eBird at featured sites.
    class MigrationSnapshot < Base
      def initialize(place:, period:, group: nil, comparison: nil)
        super()
        @area = Area.new(place)
        @period = period
        @comparison = comparison || period.previous
        @group = group
      end

      def call
        current = measure(@period)
        baseline = measure(@comparison)
        add_flags(current)
        add_evidence

        result(
          place: @area.name, period: @period.as_json, compared_with: @comparison.as_json,
          group: @group&.name || "All birds",
          current: current, baseline: baseline,
          change: change(current, baseline),
          top_species: top_species,
          coverage: { inaturalist: tier(current[:inaturalist][:bird_records], INATURALIST_TIERS),
                      ebird_checklists: tier(current[:ebird_site][:complete_checklists], CHECKLIST_TIERS) },
          notes: notes
        )
      end

      private

      def notes
        return @area.notes if @group

        @area.notes + [ "Without a species group, record counts mostly reflect how many observers were out, not how many birds." ]
      end

      def measure(period)
        { inaturalist: inaturalist(period), ebird_site: ebird_site(period), ebird_counties: ebird_counties(period) }
      end

      def inaturalist(period)
        scope = period.apply(@area.observations("inaturalist"))
        total = scope.count
        in_group = @group ? scope.where(species_group_id: @group.id).count : total

        figures = { bird_records: total, observers: scope.distinct.count(Arel.sql("details ->> 'observer'")),
                    species: scope.where.not(species_id: nil).distinct.count(:species_id),
                    confirmed_share_percent: percent(scope.where(quality_tier: "confirmed").count, total) }
        return figures unless @group

        figures.merge(group_records: in_group, group_share_percent: percent(in_group, total),
                      display: share_display(in_group, total, "bird records"))
      end

      # Reporting rate: the share of complete checklists on which the group
      # appears. Only complete checklists allow "not reported" to mean
      # "looked for and not found".
      def ebird_site(period)
        checklists = period.apply(@area.checklists).complete
        total = checklists.count
        figures = { complete_checklists: total, observer_hours: checklists.sum(:duration_hours).round(1) }
        return figures unless @group

        reporting = period.apply(Observation.where(source: "ebird", basis: "checklist", species_group_id: @group.id))
                          .where(checklist_source_id: checklists.select(:source_id)).distinct.count(:checklist_source_id)
        figures.merge(checklists_reporting: reporting, reporting_rate_percent: percent(reporting, total),
                      display: share_display(reporting, total, "complete checklists"))
      end

      # What eBird reports for the area's counties: effort, and how many
      # species (of the group) were detected.
      def ebird_counties(period)
        codes = @area.effort_county_codes
        effort = RegionDayEffort.where(source: "ebird", county_code: codes, day: period.first_day..period.last_day)
        scope = period.apply(@area.observations("ebird"))
        scope = scope.where(species_group_id: @group.id) if @group

        figures = { counties: codes.size, county_days_with_figures: effort.count, checklists: effort.sum(:checklist_count),
                    species_detected: scope.where.not(species_id: nil).distinct.count(:species_id) }
        return figures unless @group && effort.exists?

        # Coarser than a reporting rate, but available for the whole year:
        # on how many county-days with effort was the group reported at all?
        detected = scope.distinct.count(Arel.sql("(county_code, observed_on)"))
        figures.merge(county_days_group_detected: detected,
                      display: share_display(detected, figures[:county_days_with_figures], "county-days with eBird checklists"))
      end

      def change(current, baseline)
        return {} unless @group

        {
          inaturalist_share: share_change(current[:inaturalist], baseline[:inaturalist], :group_records, :bird_records, :group_share_percent),
          ebird_reporting_rate: share_change(current[:ebird_site], baseline[:ebird_site], :checklists_reporting, :complete_checklists, :reporting_rate_percent)
        }.compact
      end

      def share_change(current, baseline, part, whole, share)
        return if current[share].nil? || baseline[share].nil?

        points = (current[share] - baseline[share]).round(1)
        clear = clear_difference?(current[part], current[whole], baseline[part], baseline[whole])
        { points: points, direction: points.positive? ? "up" : points.negative? ? "down" : "unchanged",
          larger_than_chance: clear,
          display: "#{format("%+.1f", points)} percentage points (#{clear ? "larger than chance would often give" : "within what chance could give"})" }
      end

      def top_species
        scope = @period.apply(@area.observations("inaturalist")).where.not(species_id: nil)
        scope = scope.where(species_group_id: @group.id) if @group
        counts = scope.group(:species_id).order(Arel.sql("count(*) DESC")).limit(5).count
        names = Taxon.where(id: counts.keys).pluck(:id, :common_name).to_h

        counts.map { |species_id, count| { species: names[species_id], inaturalist_records: count } }
      end

      def add_flags(current)
        flag_if_recent(@period)
        if current[:inaturalist][:bird_records] < INATURALIST_TIERS[:low]
          flag("few_inaturalist_records", "Fewer than #{INATURALIST_TIERS[:low]} iNaturalist bird records in the period: shares are unreliable.")
        end
        since = @area.checklists_since
        if since && @period.first_day < since
          flag("checklists_not_held", "Full eBird checklists are only held since #{since.to_fs(:long)}; before that, eBird gives presence per county and day only.")
        elsif since && current[:ebird_site][:complete_checklists] < CHECKLIST_TIERS[:low]
          flag("few_checklists", "Fewer than #{CHECKLIST_TIERS[:low]} complete eBird checklists in the period: the reporting rate is unreliable.")
        end
        confirmed = current[:inaturalist][:confirmed_share_percent]
        if confirmed && confirmed < 70
          flag("many_unconfirmed", "Only #{confirmed.round}% of the iNaturalist records are research grade so far.")
        end
      end

      def add_evidence
        inaturalist = @period.apply(@area.observations("inaturalist"))
        inaturalist = inaturalist.where(species_group_id: @group.id) if @group
        evidence(
          title: "iNaturalist #{@group&.name&.downcase || "bird"} records, #{@area.name}, #{@period}",
          method: "Bird observations from iNaturalist located in #{@area.name}. " \
                  "The share is the group's records divided by all bird records in the same place and period.",
          source: "iNaturalist", records: inaturalist_records(inaturalist)
        )

        checklists = @period.apply(@area.checklists).complete
        return if checklists.none?

        evidence(
          title: "eBird complete checklists, #{@area.name}, #{@period}",
          method: "Complete checklists submitted to eBird within #{@area.name}. " \
                  "The reporting rate is the share of those checklists on which the group appears.",
          source: "eBird", records: checklist_records(checklists)
        )
      end
    end
  end
end
