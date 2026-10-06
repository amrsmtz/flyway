module Analytics
  module Tools
    # Shared by the analysis tools the agent can call. A tool returns plain
    # data: figures, ready-to-quote "display" strings, the caveats that
    # apply, and evidence (a description of how the figure was obtained and
    # a sample of the underlying records with their source links).
    class Base
      # Below these numbers a figure is too thin to compare.
      INATURALIST_TIERS = { low: 20, medium: 100 }.freeze
      CHECKLIST_TIERS = { low: 5, medium: 15 }.freeze
      EVIDENCE_SAMPLE = 8

      def initialize
        @evidence = []
        @flags = []
      end

      private

      # "none" when zero, then "low", "medium" or "high".
      def tier(count, thresholds)
        return "none" if count.zero?
        return "low" if count < thresholds[:low]

        count < thresholds[:medium] ? "medium" : "high"
      end

      def percent(part, whole)
        whole.zero? ? nil : (part * 100.0 / whole).round(1)
      end

      # "62% (5 of 8 complete checklists)"
      def share_display(part, whole, noun)
        return "no #{noun}" if whole.zero?

        "#{percent(part, whole).round}% (#{part} of #{whole} #{noun})"
      end

      # Two-proportion z-test at the usual 5% level: is the difference
      # between two shares larger than chance alone would often produce?
      def clear_difference?(part_a, whole_a, part_b, whole_b)
        return false if whole_a.zero? || whole_b.zero?
        # A part larger than its whole is not a share; refuse to test it.
        return false if part_a > whole_a || part_b > whole_b

        pooled = (part_a + part_b).to_f / (whole_a + whole_b)
        spread = Math.sqrt(pooled * (1 - pooled) * (1.0 / whole_a + 1.0 / whole_b))
        return false if spread.zero?

        ((part_a.to_f / whole_a - part_b.to_f / whole_b) / spread).abs > 1.96
      end

      def flag(code, message)
        @flags << { code: code, message: message }
      end

      # Adds an evidence set and returns its position, used to build its key.
      def evidence(title:, method:, records:, source:)
        @evidence << { title: title, method: method, source: source, records: records }
        @evidence.size - 1
      end

      def inaturalist_records(scope, limit: EVIDENCE_SAMPLE)
        scope.where.not(species_id: nil).order(observed_at: :desc).limit(limit).includes(:species).map do |observation|
          { label: observation.species.common_name, date: observation.observed_on.iso8601,
            detail: "#{observation.quality_tier}, by #{observation.details["observer"]}", url: observation.source_url }
        end
      end

      def checklist_records(scope, limit: EVIDENCE_SAMPLE)
        scope.order(observed_at: :desc).limit(limit).map do |checklist|
          { label: "Checklist #{checklist.source_id}", date: checklist.observed_on.iso8601,
            detail: "#{checklist.species_count} species#{", complete" if checklist.complete}", url: checklist.source_url }
        end
      end

      # A period that reaches into the last two days is still filling up:
      # observers upload late.
      def flag_if_recent(period)
        return unless period.last_day >= Date.current - 1

        flag("recent_days_incomplete", "The last two days are still receiving observations, so their counts will rise.")
      end

      def result(**figures)
        { **figures, flags: @flags, evidence: @evidence }
      end
    end
  end
end
