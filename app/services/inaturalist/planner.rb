module Inaturalist
  class Planner
    FEED = "inaturalist".freeze
    PRIORITY_LIVE = 5
    PRIORITY_BACKFILL = 50

    # One unit per day of the window, most recent first.
    def plan_backfill(days: 365, today: Date.current)
      units = (0..days).map do |days_ago|
        date = (today - days_ago).iso8601
        { kind: "day", key: date, priority: PRIORITY_BACKFILL, scope: { date: date } }
      end

      IngestionUnit.enqueue(FEED, units)
    end

    def plan_live
      IngestionUnit.schedule(feed: FEED, kind: "updates", key: "updates", scope: {}, priority: PRIORITY_LIVE,
                             refresh_after: 10.minutes)
    end
  end
end
