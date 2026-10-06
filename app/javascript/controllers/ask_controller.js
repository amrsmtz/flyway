import { Controller } from "@hotwired/stimulus"

// The question form: suggested questions, Enter to send, and a placeholder
// shown in place of the answer while it is being written.
export default class extends Controller {
  static targets = ["form", "question", "submit", "waiting", "answer"]

  suggest(event) {
    this.questionTarget.value = event.currentTarget.textContent.trim()
    this.formTarget.requestSubmit()
  }

  // Enter sends; Shift+Enter makes a new line.
  submitOnEnter(event) {
    if (event.shiftKey) return
    event.preventDefault()
    this.formTarget.requestSubmit()
  }

  start() {
    this.submitTarget.disabled = true
    this.answerTarget.classList.add("hidden")
    this.waitingTarget.classList.remove("hidden")
    this.waitingTarget.scrollIntoView({ block: "nearest" })
  }

  finish() {
    this.submitTarget.disabled = false
    this.waitingTarget.classList.add("hidden")
    this.answerTarget.classList.remove("hidden")
  }
}
