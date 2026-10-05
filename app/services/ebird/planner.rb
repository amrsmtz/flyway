module Ebird
  # Decides which eBird units exist and in what order they run. The hourly
  # quota (500 requests) cannot cover every county, so work is limited to
  # the counties that contain featured sites, most valuable days first.
  class Planner
    FEED = "ebird".freeze
    # Full checklists are only retrieved for recent days.
    CHECKLIST_WINDOW = 30.days
    # Sites the demonstration relies on; their counties are backfilled first.
    FLAGSHIP_SITES = %w[tadoussac cap-tourmente mont-royal point-pelee].freeze
    # Migration periods inside the 12-month window.
    SEASONS = [ Date.new(2025, 8, 15)..Date.new(2025, 11, 15), Date.new(2026, 3, 15)..Date.new(2026, 6, 10) ].freeze

    PRIORITY_LIVE = 5
    PRIORITY_RECENT = 20
    PRIORITY_SEASON_FLAGSHIP = 30
    PRIORITY_SEASON = 40
    PRIORITY_FLAGSHIP = 50
    PRIORITY_REST = 60

    # Queues every county and day of the window that is not queued yet.
    def plan_backfill(days: 365, today: Date.current)
      flagship = county_codes(Place.sites.where(slug: FLAGSHIP_SITES))
      counties = county_codes(Place.sites)

      units = (1..days).flat_map do |days_ago|
        date = today - days_ago
        counties.map { |county_code| county_day_unit(county_code, date, backfill_priority(date, today, flagship.include?(county_code)), today) }
      end

      IngestionUnit.enqueue(FEED, units)
    end

    # Refreshes days that are still receiving checklists: today and
    # yesterday every two hours, then three and seven days back once a day.
    def plan_live(today: Date.current)
      refresh = { 0 => 2.hours, 1 => 2.hours, 3 => 20.hours, 7 => 20.hours }

      county_codes(Place.sites).product(refresh.to_a).each do |county_code, (days_ago, refresh_after)|
        unit = county_day_unit(county_code, today - days_ago, PRIORITY_LIVE, today)
        IngestionUnit.schedule(feed: FEED, refresh_after: refresh_after, **unit)
      end
    end

    private

    def county_day_unit(county_code, date, priority, today)
      { kind: "county_day", key: "#{county_code}/#{date}", priority: priority,
        scope: { county_code: county_code, date: date.iso8601, checklists: date >= today - CHECKLIST_WINDOW } }
    end

    def backfill_priority(date, today, flagship)
      return PRIORITY_RECENT if date >= today - CHECKLIST_WINDOW

      in_season = SEASONS.any? { |season| season.cover?(date) }
      if in_season then flagship ? PRIORITY_SEASON_FLAGSHIP : PRIORITY_SEASON
      else flagship ? PRIORITY_FLAGSHIP : PRIORITY_REST
      end
    end

    # eBird counties holding at least one hotspot of the given sites.
    def county_codes(sites)
      sites.flat_map do |site|
        Place.hotspots.within_km(site.latitude, site.longitude, site.default_radius_km)
             .joins(:parent).distinct.pluck("parents_places.ebird_code")
      end.uniq
    end
  end
end
