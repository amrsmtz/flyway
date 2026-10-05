module StatusHelper
  HEALTH_LABELS = { ok: "Up to date", late: "Late", down: "Down", never: "No data yet" }.freeze
  HEALTH_CLASSES = {
    ok: "bg-green-100 text-green-800", late: "bg-amber-100 text-amber-800",
    down: "bg-red-100 text-red-800", never: "bg-gray-100 text-gray-700"
  }.freeze

  HEALTH_DOTS = { ok: "bg-green-600", late: "bg-amber-500", down: "bg-red-600", never: "bg-gray-400" }.freeze

  def feed_health_dot(status)
    HEALTH_DOTS.fetch(status.health)
  end

  def feed_health_badge(status)
    health = status.health
    tag.span(HEALTH_LABELS.fetch(health), class: "rounded px-2 py-0.5 text-sm font-medium #{HEALTH_CLASSES.fetch(health)}")
  end

  def time_ago_or_never(time)
    time ? "#{time_ago_in_words(time)} ago" : "never"
  end

  # Share of a feed's units that are finished, as a percentage.
  def queue_progress(queues, feed)
    counts = queues.select { |(unit_feed, _, _), _| unit_feed == feed }
    total = counts.values.sum
    return if total.zero?

    done = counts.select { |(_, _, status), _| status == "done" }.values.sum
    number_to_percentage(done * 100.0 / total, precision: 0)
  end
end
