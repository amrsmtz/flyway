# A raw API response, kept 30 days (TimescaleDB retention policy).
class RawPayload < ApplicationRecord
  def self.record(feed:, path:, status:, body:)
    insert({ fetched_at: Time.current, feed: feed, path: path, status: status, body: body })
  end
end
