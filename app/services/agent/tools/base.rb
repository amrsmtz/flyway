module Agent
  module Tools
    # Bridge between the language model and the analysis tools. The model
    # passes a place name and dates as text; this layer resolves the place
    # in the gazetteer, validates the dates, runs the analysis and hands
    # back a compact result. Problems come back as an "error" the model can
    # read, never as an exception.
    class Base < RubyLLM::Tool
      GROUPS_HINT = "One of: warblers, snow_goose, raptors. Leave out for all birds.".freeze
      WINDOW_DAYS = 365

      def initialize(run)
        super()
        @run = run
      end

      def execute(**arguments)
        return @run.record_error(tool: name, arguments: arguments, message: "Tool budget used up; answer with what you have.") unless @run.budget_left?

        resolution = Places::Resolver.new.call(arguments[:place].to_s)
        place = resolution.candidates.first&.place
        return @run.record_error(tool: name, arguments: arguments, message: unknown_place(arguments[:place], resolution)) unless place

        period = period(arguments[:date_from], arguments[:date_to])
        result = analyse(place: place, period: period, **arguments.except(:place, :date_from, :date_to))
        @run.record(tool: name, arguments: arguments, result: result, place: understood_as(resolution))
      rescue ArgumentError, Date::Error => e
        @run.record_error(tool: name, arguments: arguments, message: "Invalid request: #{e.message}")
      end

      private

      def period(from, to)
        period = Analytics::Period.parse(from, to)
        today = Date.current
        raise ArgumentError, "date_from is after date_to" if period.first_day > period.last_day
        raise ArgumentError, "dates must fall between #{today - WINDOW_DAYS} and #{today}; no older data is held" if period.first_day < today - WINDOW_DAYS || period.first_day > today

        Analytics::Period.new(first_day: period.first_day, last_day: [ period.last_day, today ].min)
      end

      def optional_period(from, to)
        period(from, to) if from.present? && to.present?
      end

      def group(key)
        return if key.blank? || key == "all"

        SpeciesGroup.find_by(key: key) or raise ArgumentError, "unknown group #{key}. #{GROUPS_HINT}"
      end

      # How the place name was read. Doubt (an approximate or ambiguous
      # match) follows a semicolon, and the answer must mention it.
      def understood_as(resolution)
        best = resolution.candidates.first
        text = "#{best.place.name} (#{PlacesController.helpers.place_kind_label(best.place).downcase}), exact match"
        others = resolution.candidates.drop(1).first(2).map { |candidate| "#{candidate.place.name} (#{candidate.place.kind})" }

        case resolution.status
        when :approximate then "#{text.sub(", exact match", "")}; APPROXIMATE match on the name given: mention it"
        when :ambiguous then "#{text.sub(", exact match", "")}; AMBIGUOUS, other places share this name: #{others.join(", ")}: say which one was used"
        else text
        end
      end

      def unknown_place(name, resolution)
        suggestions = resolution.suggestions.first(3).map { |candidate| candidate.place.name }
        message = "No place called #{name.inspect} in Quebec, Ontario or the Maritimes."
        suggestions.any? ? "#{message} Similar names: #{suggestions.join(", ")}." : message
      end
    end
  end
end
