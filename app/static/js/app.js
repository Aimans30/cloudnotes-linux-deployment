// CloudNotes progressive enhancements. Forms work without this script.
(function () {
  "use strict";

  // Ask for confirmation before submitting forms marked with data-confirm.
  document.addEventListener("submit", function (event) {
    var form = event.target;
    var message = form.getAttribute("data-confirm");
    if (message && !window.confirm(message)) {
      event.preventDefault();
    }
  });

  // Show a loading state on the submit button while the request is in flight.
  document.addEventListener("submit", function (event) {
    var form = event.target;
    if (event.defaultPrevented) {
      return;
    }
    var button = form.querySelector("button[type='submit'][data-loading-text]");
    if (!button) {
      return;
    }
    button.dataset.originalText = button.textContent;
    button.setAttribute("aria-busy", "true");
    button.disabled = true;
    button.textContent = button.getAttribute("data-loading-text");
  });

  // Restore buttons when the browser returns to the page from the back/forward cache.
  window.addEventListener("pageshow", function () {
    document.querySelectorAll("button[aria-busy='true']").forEach(function (button) {
      button.removeAttribute("aria-busy");
      button.disabled = false;
      button.textContent = button.dataset.originalText || button.textContent;
    });
  });
})();
