(() => {
  "use strict";

  document.documentElement.classList.add("has-js");

  const release = window.TaneClientRelease;
  if (release) {
    document.querySelectorAll("[data-release-version]").forEach((element) => {
      element.textContent = element.dataset.releaseVersion === "tag"
        ? release.tag
        : release.version;
    });

    document.querySelectorAll("[data-release-filename]").forEach((element) => {
      element.textContent = release.filename;
    });

    const destinations = {
      download: release.downloadUrl,
      release: release.releaseUrl,
      repository: release.repositoryUrl
    };
    document.querySelectorAll("[data-release-href]").forEach((link) => {
      const destination = destinations[link.dataset.releaseHref];
      if (destination) {
        link.href = destination;
      }
    });
  }

  const revealElements = Array.from(document.querySelectorAll(".reveal"));
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reducedMotion || !("IntersectionObserver" in window)) {
    revealElements.forEach((element) => element.classList.add("is-visible"));
    return;
  }

  const observer = new IntersectionObserver((entries, activeObserver) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) {
        return;
      }
      entry.target.classList.add("is-visible");
      activeObserver.unobserve(entry.target);
    });
  }, { rootMargin: "0px 0px -8%", threshold: 0.08 });

  revealElements.forEach((element) => observer.observe(element));
})();
