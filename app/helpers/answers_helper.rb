module AnswersHelper
  CONFIDENCE_CLASSES = {
    "high" => "bg-green-100 text-green-800", "medium" => "bg-amber-100 text-amber-800", "low" => "bg-red-100 text-red-800"
  }.freeze

  def confidence_badge(answer)
    tag.span("#{answer.confidence.capitalize} confidence",
             class: "rounded px-2 py-0.5 text-sm font-medium #{CONFIDENCE_CLASSES.fetch(answer.confidence)}")
  end

  # "eBird collected 12 minutes ago"
  def freshness_sentence(answer)
    answer.freshness.map do |feed|
      collected = feed["collected_at"] ? "#{time_ago_in_words(Time.iso8601(feed["collected_at"]))} ago" : "never"
      "#{feed["name"]} collected #{collected}"
    end.to_sentence
  end

  # Where and when to point the map for an answer: the place, last day and
  # group of its first tool call.
  def answer_map_view(answer)
    call = answer.tool_results.find { |entry| entry["error"].nil? }
    return unless call

    place = Places::Resolver.new.call(call.dig("arguments", "place").to_s).candidates.first&.place
    return unless place

    box = Analytics::Area.new(place).box
    { bounds: [ box[:min_longitude], box[:min_latitude], box[:max_longitude], box[:max_latitude] ],
      date: call.dig("arguments", "date_to"), group: call.dig("arguments", "group").presence || "all" }
  end
end
