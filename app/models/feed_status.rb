# Health of one feed, as shown to users and passed to the agent.
class FeedStatus < ApplicationRecord
  FEEDS = %w[ebird inaturalist open_meteo].freeze

  validates :feed, inclusion: { in: FEEDS }

  def self.for(feed)
    create_or_find_by!(feed: feed)
  end

  def self.record_success(feed, latest_data_at: nil, remaining_quota: nil)
    status = self.for(feed)
    status.update!(
      last_success_at: Time.current,
      latest_data_at: [ status.latest_data_at, latest_data_at ].compact.max,
      remaining_quota: remaining_quota || status.remaining_quota
    )
  end

  def self.record_failure(feed, error)
    self.for(feed).update!(last_failure_at: Time.current, last_error: error.to_s.first(250))
  end

  def self.pause(feed, until_time, reason)
    self.for(feed).update!(paused_until: until_time, last_failure_at: Time.current, last_error: reason.to_s.first(250))
  end

  def paused?
    paused_until.present? && paused_until.future?
  end
end
