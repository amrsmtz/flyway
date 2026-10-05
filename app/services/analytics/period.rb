module Analytics
  # A range of local calendar days, inclusive.
  Period = Data.define(:first_day, :last_day) do
    def self.parse(from, to)
      new(first_day: Date.iso8601(from.to_s), last_day: Date.iso8601(to.to_s))
    end

    def days
      (last_day - first_day).to_i + 1
    end

    # The period of the same length that ends the day before this one.
    def previous
      self.class.new(first_day: first_day - days, last_day: first_day - 1)
    end

    # Filters a hypertable scope with observed_at and observed_on columns.
    # The padded time range lets TimescaleDB skip chunks; the date range is
    # the exact filter.
    def apply(scope)
      scope.where(observed_at: (first_day - 1).beginning_of_day..(last_day + 1).end_of_day, observed_on: first_day..last_day)
    end

    def to_s
      first_day == last_day ? first_day.to_fs(:long) : "#{first_day.to_fs(:long)} to #{last_day.to_fs(:long)}"
    end

    def as_json(*)
      { from: first_day.iso8601, to: last_day.iso8601, days: days }
    end
  end
end
