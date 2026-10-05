module OpenMeteo
  class Planner
    FEED = "open_meteo".freeze
    PRIORITY_LIVE = 5
    PRIORITY_BACKFILL = 50
    # Points per request.
    GROUP_SIZE = 10
    LIVE_GROUP_SIZE = 50

    # One unit per group of points and calendar month, most recent first.
    def plan_backfill(months: 12, today: Date.current)
      groups = WeatherPoint.order(:id).pluck(:id).each_slice(GROUP_SIZE).to_a

      units = (0..months).flat_map do |months_ago|
        month = today.beginning_of_month << months_ago
        start_date = [ month, today - 365 ].max
        end_date = [ month.end_of_month, today ].min

        groups.each_with_index.map do |point_ids, index|
          { kind: "period", key: "#{month.strftime("%Y-%m")}/group-#{index}", priority: PRIORITY_BACKFILL + months_ago,
            scope: { point_ids: point_ids, start_date: start_date.iso8601, end_date: end_date.iso8601 } }
        end
      end

      IngestionUnit.enqueue(FEED, units)
    end

    def plan_live
      WeatherPoint.order(:id).pluck(:id).each_slice(LIVE_GROUP_SIZE).each_with_index do |point_ids, index|
        IngestionUnit.schedule(feed: FEED, kind: "live", key: "group-#{index}", scope: { point_ids: point_ids },
                               priority: PRIORITY_LIVE, refresh_after: 2.hours)
      end
    end
  end
end
