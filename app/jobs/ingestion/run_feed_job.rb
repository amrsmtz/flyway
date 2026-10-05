module Ingestion
  # Drains a feed's queue for under a minute. Scheduled every minute; the
  # concurrency limit keeps runs of the same feed from overlapping.
  class RunFeedJob < ApplicationJob
    limits_concurrency to: 1, key: ->(feed) { feed }, duration: 5.minutes

    def perform(feed)
      Runner.new(feed).call
    end
  end
end
