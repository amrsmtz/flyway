module Analytics
  module Tools
    # Where there is too little observation to conclude anything. The area
    # is cut into H3 cells (resolution 4, about 1,800 km²); each cell's
    # records in the period are set against its own activity over the year,
    # so a cell that is usually well watched and silent now stands out from
    # one where nobody ever reports.
    class CoverageReport < Base
      ENOUGH = INATURALIST_TIERS[:low]
      # A cell is "usually watched" from this many records a year.
      USUAL_YEARLY_RECORDS = 100
      LIMIT = 10
      CELL_SQL = "h3_cell_to_parent(h3_cell::h3index, 4)::bigint".freeze

      def initialize(place:, period:)
        super()
        @area = Area.new(place)
        @period = period
      end

      def call
        yearly = cell_counts(Period.new(first_day: Date.current - 365, last_day: Date.current))
        current = cell_counts(@period)
        usual = yearly.select { |_, count| count >= USUAL_YEARLY_RECORDS }.keys
        gaps = usual.select { |cell| current[cell].to_i < ENOUGH }.sort_by { |cell| -yearly[cell] }
        counties = thin_counties
        add_evidence(gaps)

        result(
          place: @area.name, period: @period.as_json,
          cell_size: "hexagons of about 1,800 km²",
          cells: { with_records_this_year: yearly.size, usually_watched: usual.size,
                   enough_records_now: usual.count { |cell| current[cell].to_i >= ENOUGH },
                   too_few_records_now: gaps.count { |cell| current[cell].to_i.positive? },
                   no_records_now: gaps.count { |cell| current[cell].to_i.zero? } },
          threshold: "#{ENOUGH} iNaturalist bird records in the period",
          least_covered_usually_watched_areas: describe(gaps.first(LIMIT), current, yearly),
          ebird_counties_with_few_checklists: counties,
          reminder: "No records means nobody reported, not that no birds were there.", notes: @area.notes
        )
      end

      private

      def cell_counts(period)
        period.apply(@area.observations("inaturalist")).where(obscured: false).group(Arel.sql(CELL_SQL)).count
      end

      def describe(cells, current, yearly)
        return [] if cells.empty?

        sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, cells ])
          SELECT cell, (h3_cell_to_latlng(cell::h3index))[0], (h3_cell_to_latlng(cell::h3index))[1]
          FROM unnest(ARRAY[?]::bigint[]) AS cell
        SQL
        centres = ActiveRecord::Base.connection.select_rows(sql).to_h { |cell, longitude, latitude| [ cell, [ latitude, longitude ] ] }

        cells.map do |cell|
          latitude, longitude = centres.fetch(cell)
          { around: nearest_town(latitude, longitude), records_now: current[cell].to_i,
            usual_records_for_this_many_days: (yearly[cell] * @period.days / 365.0).round }
        end
      end

      # Largest town within 40 km of a cell's centre, else the nearest one.
      def nearest_town(latitude, longitude)
        nearby = Place.cities.within_km(latitude, longitude, 40).order(importance: :desc).first
        nearest = ApplicationRecord.sanitize_sql_array([ "abs(latitude - ?) + abs(longitude - ?)", latitude, longitude ])
        town = nearby || Place.cities.order(Arel.sql(nearest)).first
        "#{town.name}, #{town.province_code.delete_prefix("CA-")}"
      end

      # Counties where eBird itself reports fewer than five checklists.
      def thin_counties
        efforts = RegionDayEffort.where(source: "ebird", county_code: @area.effort_county_codes,
                                        day: @period.first_day..@period.last_day).group(:county_code).sum(:checklist_count)
        names = Place.counties.where(ebird_code: efforts.keys).pluck(:ebird_code, :name).to_h

        efforts.select { |_, checklists| checklists < CHECKLIST_TIERS[:low] }
               .map { |code, checklists| { county: names[code], checklists: checklists } }
      end

      def add_evidence(gaps)
        evidence(
          title: "Observation coverage, #{@area.name}, #{@period}",
          method: "iNaturalist bird records counted per hexagonal cell of about 1,800 km². A cell is usually watched when it " \
                  "has at least #{USUAL_YEARLY_RECORDS} records over the last 12 months, and has too few now below #{ENOUGH} records " \
                  "in the period. Records with obscured positions are left out. #{gaps.size} usually watched cells are below the threshold.",
          source: "iNaturalist", records: []
        )
      end
    end
  end
end
