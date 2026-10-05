# Health of one feed, as shown to users and passed to the agent.
class FeedStatus < ApplicationRecord
  FEEDS = %w[ebird inaturalist open_meteo].freeze
  NAMES = { "ebird" => "eBird", "inaturalist" => "iNaturalist", "open_meteo" => "Open-Meteo" }.freeze
  # How long a feed may go without a successful run before it counts as
  # late. Beyond three times that, it counts as down.
  EXPECTED_INTERVALS = { "ebird" => 3.hours, "inaturalist" => 1.hour, "open_meteo" => 4.hours }.freeze

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

  def name
    NAMES.fetch(feed)
  end

  # :ok, :late, :down, or :never when the feed has not succeeded yet.
  def health(now: Time.current)
    return :never if last_success_at.nil?

    age = now - last_success_at
    interval = EXPECTED_INTERVALS.fetch(feed)
    if age <= interval then :ok
    elsif age <= interval * 3 then :late
    else :down
    end
  end
end
