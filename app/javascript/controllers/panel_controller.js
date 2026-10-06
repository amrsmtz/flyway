import { Controller } from "@hotwired/stimulus"

// Folds the question panel away to give its width (or, on small screens, its
// height) back to the map. The map follows the change in size on its own.
export default class extends Controller {
  static targets = ["panel", "toggle"]

  toggle() {
    const open = !this.panelTarget.classList.toggle("hidden")
    this.toggleTargets.forEach((button) => button.setAttribute("aria-expanded", open))
  }
}
