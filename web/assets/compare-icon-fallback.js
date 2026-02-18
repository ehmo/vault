(function () {
  const fallbackIcon = "/assets/compare-fallback-icon.svg";

  function attachFallbackHandlers() {
    const targets = document.querySelectorAll('img[src*="is1-ssl.mzstatic.com"], img[data-competitor-icon]');

    targets.forEach((img) => {
      if (img.dataset.fallbackBound === "1") return;
      img.dataset.fallbackBound = "1";

      img.addEventListener("error", () => {
        if (img.dataset.fallbackApplied === "1") return;
        img.dataset.fallbackApplied = "1";
        img.src = fallbackIcon;
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", attachFallbackHandlers, { once: true });
  } else {
    attachFallbackHandlers();
  }
})();
