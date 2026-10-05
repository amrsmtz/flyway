# One unit of ingestion work for a feed. Units are claimed one at a time,
# retried with a growing delay when the source is unavailable, and marked
# dead when they keep failing, so a problem stays visible instead of looping.
class IngestionUnit < ApplicationRecord
  STATUSES = %w[pending running done dead].freeze
  MAX_ATTEMPTS = 5
  # A unit still "running" after this long belonged to a process that died.
  STALE_AFTER = 15.minutes

  validates :feed, :kind, :key, presence: true
  validates :status, inclusion: { in: STATUSES }

  STATUSES.each { |status| scope status, -> { where(status: status) } }
  scope :due, -> { pending.where(next_attempt_at: ..Time.current) }

  # Adds units, ignoring those that already exist. Each row needs :kind,
  # :key, :scope and :priority.
  def self.enqueue(feed, rows)
    return 0 if rows.empty?

    insert_all(rows.map { |row| row.merge(feed: feed) }, unique_by: %i[feed kind key]).length
  end

  # Adds a unit, or sends a finished one back to the queue when its result
  # is older than refresh_after. Used for data that keeps changing, such as
  # today's observations.
  def self.schedule(feed:, kind:, key:, scope:, priority:, refresh_after:)
    unit = create_or_find_by!(feed: feed, kind: kind, key: key) do |new_unit|
      new_unit.assign_attributes(scope: scope, priority: priority)
    end
    return unit unless unit.status.in?(%w[done dead]) && unit.finished_at < refresh_after.ago

    unit.update!(status: "pending", priority: priority, scope: scope, attempts: 0, next_attempt_at: Time.current)
    unit
  end

  # Takes the most urgent due unit of a feed. SKIP LOCKED lets several
  # workers claim different units without waiting on each other.
  def self.claim_next(feed)
    transaction do
      unit = due.where(feed: feed).order(:priority, :next_attempt_at, :id).lock("FOR UPDATE SKIP LOCKED").first
      unit&.update!(status: "running", started_at: Time.current, attempts: unit.attempts + 1)
      unit
    end
  end

  def self.release_stale
    running.where(started_at: ..STALE_AFTER.ago).update_all(status: "pending")
  end

  def complete!(records_count)
    update!(status: "done", records_count: records_count, last_error: nil, finished_at: Time.current)
  end

  # Back to the queue without counting an attempt: the source asked us to
  # wait, the unit itself did nothing wrong.
  def postpone!(until_time)
    update!(status: "pending", attempts: attempts - 1, next_attempt_at: until_time)
  end

  def fail!(error, retryable:)
    if retryable && attempts < MAX_ATTEMPTS
      update!(status: "pending", last_error: error.to_s.first(250), next_attempt_at: retry_delay.from_now)
    else
      update!(status: "dead", last_error: error.to_s.first(250), finished_at: Time.current)
    end
  end

  private

  # 2, 4, 8, 16 minutes.
  def retry_delay
    (2**attempts).minutes
  end
end
