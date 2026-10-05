class AgentAnswer < ApplicationRecord
  STATUSES = %w[answered cannot_answer failed].freeze
  CONFIDENCE_LEVELS = %w[high medium low].freeze
  # A cached answer is reused for this long; the data moves every few minutes.
  FRESH_FOR = 45.minutes
  # Offered as one-click questions on the home page. They are answered ahead
  # of time by a recurring job, so a click costs no model call, and stay
  # fresh longer to spare the model's daily quota.
  SUGGESTED = [
    "Is there a migration wave in southern Quebec right now, and is the weather favourable?",
    "Did last night's north winds bring more warblers to Tadoussac?",
    "Compare this fall's snow goose migration at Cap Tourmente with last spring's.",
    "Which areas have too few observations to draw any conclusion?"
  ].freeze
  SUGGESTED_FRESH_FOR = 3.hours
  # Upper bounds on questions sent to the model, all visitors together. The
  # free tier allows the fallback model 5 requests a minute and the primary
  # one somewhat more (it refused after about 18 in a minute); a question
  # takes two requests.
  DAILY_LIMIT = 300
  MINUTE_LIMIT = 6

  validates :question, :question_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  def self.question_key_for(question, today: Date.current)
    "#{today.iso8601}|#{question.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip}"
  end

  # Most recent usable answer to the same question, if still fresh.
  def self.fresh_for(question)
    fresh_for = SUGGESTED.include?(question) ? SUGGESTED_FRESH_FOR : FRESH_FOR
    usable_for(question).where(created_at: fresh_for.ago..).last
  end

  # Most recent usable answer to the same question asked today, whatever
  # its age: better than nothing when the model cannot be reached.
  def self.latest_for(question)
    usable_for(question).last
  end

  def self.usable_for(question)
    where(question_key: question_key_for(question)).where.not(status: "failed").order(:created_at)
  end

  def self.limit_reached?
    asked = where.not(model: nil)
    asked.where(created_at: 1.minute.ago..).count >= MINUTE_LIMIT ||
      asked.where(created_at: Time.current.beginning_of_day..).count >= DAILY_LIMIT
  end

  def evidence_set(key)
    evidence.find { |set| set["key"] == key }
  end

  def text
    answer["answer"]
  end

  def key_figures
    answer["key_figures"].to_a
  end

  def caveats
    answer["caveats"].to_a
  end
end
