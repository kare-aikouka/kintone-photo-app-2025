// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import $ from "jquery";
window.$ = $;
window.jQuery = $;
import * as bootstrap from "bootstrap"
import "./signin.js";

document.addEventListener("DOMContentLoaded", () => {
  const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
  tooltipTriggerList.map(function (tooltipTriggerEl) {
    return new bootstrap.Tooltip(tooltipTriggerEl)
  })
})

