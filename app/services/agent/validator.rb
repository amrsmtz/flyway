module Agent
  # Checks the model's answer against what the tools actually returned:
  # citations must point at existing evidence, and numbers must come from
  # the tool results (or from the question itself).
  class Validator
    NUMBER = /\d+(?:[.,]\d+)*/

    def initialize(answer:, run:, question:)
      @answer = answer
      @run = run
      @question = question
    end

    # The answer with citations to unknown evidence removed.
    def cleaned
      known = @run.evidence.pluck(:key)
      figures = @answer["key_figures"].to_a.map { |figure| figure.merge("evidence" => figure["evidence"].to_a & known) }
      @answer.merge("key_figures" => figures)
    end

    # Numbers in the answer that cannot be traced to a tool result. Single
    # digits are let through: they are mostly counts written in passing.
    def unverified_numbers
      allowed = numbers(@run.tool_results.to_json) | numbers(@question)
      stated = numbers([ @answer["answer"], *@answer["key_figures"].to_a.pluck("text") ].join(" "))

      stated.reject { |number| number < 10 || allowed.any? { |known| close?(number, known) } }.map { |number| format_number(number) }
    end

    private

    def numbers(text)
      text.to_s.scan(NUMBER).map { |token| token.delete(",").to_f }.uniq
    end

    # The model may round: 7.7 can be written 8, and 62.3 as 62.
    def close?(stated, known)
      (stated - known).abs < 0.05 || stated == known.round || stated == known.floor || stated == known.round(1)
    end

    def format_number(number)
      number == number.to_i ? number.to_i.to_s : number.to_s
    end
  end
end
