import { Controller } from "@hotwired/stimulus"

// The question form: suggested questions, Enter to send, and a waiting
// state while the answer is being written.
export default class extends Controller {
  static targets = ["form", "question", "submit", "waiting"]

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
    this.waitingTarget.classList.remove("hidden")
  }

  finish() {
    this.submitTarget.disabled = false
    this.waitingTarget.classList.add("hidden")
  }
}
