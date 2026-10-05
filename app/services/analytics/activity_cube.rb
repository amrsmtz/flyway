module Analytics
  # Everything the map needs to replay a year of observations without
  # another request: for each day, the hexagonal cells with records and,
  # per source, the number of records in total and per featured group.
  #
  # The layout is compact on purpose (see #as_json); the browser sums and
  # colours cells itself while the timeline is scrubbed.
  class ActivityCube
    RESOLUTIONS = [ 4, 5 ].freeze
    SOURCES = %w[inaturalist ebird].freeze
    TIME_ZONE = "America/Toronto".freeze

    def initialize(resolution: 4, days: 365, today: Date.current)
      raise ArgumentError, "unsupported resolution" unless RESOLUTIONS.include?(resolution)

      @resolution = resolution
      @first_day = today - days
      @last_day = today
      @groups = SpeciesGroup.order(:id).pluck(:id, :key)
    end

    def as_json(*)
      rows = fetch_rows
      cells = rows.map(&:first).uniq.sort
      cell_index = cells.each_with_index.to_h

      {
        resolution: @resolution,
        first_day: @first_day.iso8601,
        day_count: (@last_day - @first_day).to_i + 1,
        # Order of the numbers that follow each cell index in "days".
        series: SOURCES.product([ "all", *@groups.map(&:last) ]).map { |source, group| "#{source}:#{group}" },
        cells: boundaries(cells),
        days: days(rows, cell_index)
      }
    end

    private

    # [cell, day offset, source, species_group_id or nil, record count]
    def fetch_rows
      cell = @resolution == 5 ? "cell" : "h3_cell_to_parent(cell::h3index, #{@resolution})::bigint"

      ObservationDailyCell
        .where(day: @first_day.in_time_zone(TIME_ZONE)..@last_day.in_time_zone(TIME_ZONE).end_of_day, source: SOURCES)
        .group(Arel.sql(cell), Arel.sql("(day AT TIME ZONE '#{TIME_ZONE}')::date"), :source, :species_group_id)
        .pluck(Arel.sql(cell), Arel.sql("(day AT TIME ZONE '#{TIME_ZONE}')::date"), :source, :species_group_id,
               Arel.sql("sum(record_count)::int"))
    end

    # One flat array per day: cell index followed by one count per series,
    # repeated for each cell that has records that day.
    def days(rows, cell_index)
      width = SOURCES.size * (@groups.size + 1)
      group_offset = @groups.each_with_index.to_h { |(id, _), index| [ id, index + 1 ] }
      by_day = Hash.new { |hash, day| hash[day] = Hash.new { |cells, cell| cells[cell] = Array.new(width, 0) } }

      rows.each do |cell, day, source, group_id, count|
        counts = by_day[(day - @first_day).to_i][cell_index.fetch(cell)]
        base = SOURCES.index(source) * (@groups.size + 1)
        counts[base] += count
        counts[base + group_offset.fetch(group_id)] += count if group_id
      end

      Array.new((@last_day - @first_day).to_i + 1) { |offset| by_day.key?(offset) ? by_day[offset].flat_map { |index, counts| [ index, *counts ] } : [] }
    end

    # Hexagon outlines as [[longitude, latitude], ...], in cell-index order.
    def boundaries(cells)
      return [] if cells.empty?

      sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, cells ])
        SELECT cell, h3_cell_to_boundary(cell::h3index)::text
        FROM unnest(ARRAY[?]::bigint[]) AS cell
      SQL
      outlines = ActiveRecord::Base.connection.select_rows(sql).to_h

      cells.map { |cell| outlines.fetch(cell).scan(/-?\d+\.?\d*/).map { |number| number.to_f.round(4) }.each_slice(2).to_a }
    end
  end
end
