module Ingestion
  # Works through the pending units of one feed for a limited time, then
  # stops; a recurring job starts it again. Each unit is handled on its own,
  # so one failure never blocks the rest of the queue.
  class Runner
    # Raised by a handler when the source says to stop until a given time.
    class Paused < StandardError
      attr_reader :until_time

      def initialize(until_time, reason)
        @until_time = until_time
        super(reason)
      end
    end

    # Raised by a handler when the source failed in a way worth retrying.
    class Retryable < StandardError; end

    HANDLERS = {
      "ebird" => {
        "county_day" => "Ebird::CountyDayHandler",
        "checklist" => "Ebird::ChecklistHandler"
      }
    }.freeze

    def initialize(feed, time_budget: 50.seconds)
      @feed = feed
      @time_budget = time_budget
      @handlers = {}
    end

    # Returns the number of units completed.
    def call
      deadline = @time_budget.from_now
      completed = 0
      IngestionUnit.release_stale

      while Time.current < deadline && !FeedStatus.for(@feed).paused?
        unit = IngestionUnit.claim_next(@feed) or break
        completed += 1 if process(unit)
      end

      completed
    end

    private

    def process(unit)
      result = handler_for(unit).call(unit)
      unit.complete!(result.fetch(:records))
      FeedStatus.record_success(@feed, **result.slice(:latest_data_at, :remaining_quota))
      true
    rescue Paused => e
      unit.postpone!(e.until_time)
      FeedStatus.pause(@feed, e.until_time, e.message)
      false
    rescue Retryable => e
      fail_unit(unit, e, retryable: true)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { unit: unit.id })
      fail_unit(unit, e, retryable: false)
    end

    def fail_unit(unit, error, retryable:)
      unit.fail!("#{error.class}: #{error.message}", retryable: retryable)
      FeedStatus.record_failure(@feed, error.message)
      false
    end

    # One handler instance per kind and run, so it can keep an API client
    # and lookup tables between units.
    def handler_for(unit)
      @handlers[unit.kind] ||= HANDLERS.fetch(unit.feed).fetch(unit.kind).constantize.new
    end
  end
end
