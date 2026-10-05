module Agent
  # The confidence shown with an answer. It is computed here from the data,
  # not chosen by the language model: the same evidence always gives the
  # same level, with the reasons spelled out.
  class Confidence
    # Flags that make a conclusion unsafe, and flags that only weaken it.
    LOW = %w[few_inaturalist_records few_checklists few_nights ebird_not_collected].freeze
    MEDIUM = %w[recent_days_incomplete many_unconfirmed includes_forecast unequal_effort checklists_not_held].freeze
    MAX_REASONS = 4

    def initialize(run:, freshness:, unverified_numbers:, cannot_answer:)
      @run = run
      @freshness = freshness
      @unverified_numbers = unverified_numbers
      @cannot_answer = cannot_answer
    end

    # [level, reasons]
    def assess
      low = reasons_for(LOW) + stale_feeds("down") + unverified
      medium = reasons_for(MEDIUM) + stale_feeds("late") + place_doubts
      low << "The data held cannot answer this question." if @cannot_answer

      level = if low.any? then "low" elsif medium.any? then "medium" else "high" end
      reasons = (low + medium).uniq.first(MAX_REASONS)
      [ level, reasons.presence || [ "Enough observations, from feeds that are up to date, with no warning raised." ] ]
    end

    private

    def reasons_for(codes)
      @run.flags.select { |flag| codes.include?(flag[:code]) }.pluck(:message)
    end

    def stale_feeds(health)
      @freshness.select { |feed| feed[:health] == health }.map do |feed|
        "#{feed[:name]} data is #{health == "down" ? "badly out of date" : "later than usual"}."
      end
    end

    def unverified
      return [] if @unverified_numbers.empty?

      [ "Some figures in the answer could not be traced to the data (#{@unverified_numbers.join(", ")})." ]
    end

    def place_doubts
      @run.tool_results.filter_map { |entry| entry[:place] }.uniq.select { |place| place.include?(";") }.map do |place|
        "Place name was not matched exactly: #{place.split(";").first}."
      end
    end
  end
end
