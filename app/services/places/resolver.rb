module Places
  # Turns a place name typed by a person into ranked gazetteer candidates,
  # and says how sure it is. It never guesses silently: an approximate or
  # ambiguous match is reported as such, with the alternatives.
  class Resolver
    # When several kinds of place share a name, the earlier kind wins:
    # "Tadoussac" is the birding site before the village, "Quebec" the
    # province before the city, "Charlevoix" the region before the county.
    KIND_PRIORITY = %w[site province region city county hotspot].freeze
    # Trigram similarity above which a fuzzy match is offered as the answer;
    # weaker matches are only listed as suggestions.
    APPROXIMATE_THRESHOLD = 0.45
    LEADING_WORDS = /\A(?:(?:near|around|in|at|close to|the|city of|town of|pres de|autour de)\s+)+/
    TRAILING_WORDS = /\s+(?:area|region)\z/
    MAX_CANDIDATES = 5

    # status is :found, :ambiguous (several places of the same kind share
    # the name), :approximate (best match is fuzzy) or :not_found.
    Result = Data.define(:query, :status, :candidates, :suggestions, :province)
    Candidate = Data.define(:place, :match, :similarity, :matched_name)

    def call(query)
      text = PlaceAlias.normalize(query)
      # The whole text first: "Southern Quebec" is a region, not a place
      # called "Southern" in Quebec. Only then is a trailing province split off.
      attempts = [ [ text, nil ], extract_province(text) ].compact.reject { |name, _| name.blank? }

      matches, province = exact_match(attempts)
      if matches.empty? && attempts.any?
        name, province = attempts.last
        matches = fuzzy_candidates(variants(name).last, province)
      end
      candidates, suggestions = matches.partition { |candidate| candidate.similarity >= APPROXIMATE_THRESHOLD }

      Result.new(query:, status: status_for(candidates), candidates: candidates.first(MAX_CANDIDATES),
                 suggestions: suggestions.first(MAX_CANDIDATES), province:)
    end

    private

    def exact_match(attempts)
      attempts.each do |name, province|
        variants(name).each do |variant|
          candidates = exact_candidates(variant, province)
          return [ candidates, province ] if candidates.any?
        end
      end

      [ [], nil ]
    end

    # The name as typed, then with filler words removed step by step
    # ("near Montreal", "the Tadoussac area"). Longer forms go first because
    # some aliases contain those words ("Montreal area").
    def variants(text)
      without_leading = text.sub(LEADING_WORDS, "")
      [ text, without_leading, without_leading.sub(TRAILING_WORDS, "") ].reject(&:blank?).uniq
    end

    # "Kingston, Nova Scotia" or "Kingston NS": a trailing province narrows
    # the search. Returns nil when the text does not end with a province.
    def extract_province(text)
      province_names.each do |name, province|
        return [ text.delete_suffix(" #{name}"), province ] if text.end_with?(" #{name}")
      end

      nil
    end

    def province_names
      @province_names ||= PlaceAlias.joins(:place).where(places: { kind: "province" })
                                    .pluck(:normalized_name, "places.province_code")
                                    .sort_by { |name, _| -name.length }
    end

    def exact_candidates(text, province)
      places = scoped(province).joins(:aliases).where(place_aliases: { normalized_name: text }).distinct
      rank(places.map { |place| Candidate.new(place:, match: :exact, similarity: 1.0, matched_name: place.name) })
    end

    def fuzzy_candidates(text, province)
      quoted = PlaceAlias.connection.quote(text)
      matches = PlaceAlias.where("normalized_name % ?", text)
                          .select("DISTINCT ON (place_id) place_id, name, similarity(normalized_name, #{quoted}) AS similarity")
                          .order(Arel.sql("place_id, similarity(normalized_name, #{quoted}) DESC"))
                          .index_by(&:place_id)

      candidates = scoped(province).where(id: matches.keys).map do |place|
        match = matches.fetch(place.id)
        Candidate.new(place:, match: :approximate, similarity: match.similarity.round(2), matched_name: match.name)
      end
      rank(candidates)
    end

    def scoped(province)
      province ? Place.where(province_code: province) : Place.all
    end

    # Closest name first, then kind, then importance (population for
    # cities, checklists for sites and hotspots).
    def rank(candidates)
      candidates.sort_by do |candidate|
        [ -candidate.similarity, KIND_PRIORITY.index(candidate.place.kind), -candidate.place.importance ]
      end
    end

    def status_for(candidates)
      best = candidates.first
      return :not_found unless best
      return :approximate if best.match == :approximate

      same_kind = candidates.count { |candidate| candidate.match == :exact && candidate.place.kind == best.place.kind }
      same_kind > 1 ? :ambiguous : :found
    end
  end
end
