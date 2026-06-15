// popover-demo.js — vanilla, dependency-free (loaded with defer like i18n.js).
// Owns three things on the 2.0 marketing site:
//   1. The interactive popover demo: a WAI-ARIA tabs widget that swaps the four
//      2.0 popover screenshots (CPU / RAM / Network-Disk / AI tokens).
//   2. The scroll-reveal IntersectionObserver that adds .reveal-in to
//      .reveal-init blocks as they enter the viewport.
//   3. Suppressing the sticky download CTA while the hero or the #download panel
//      is on screen, so the primary action never doubles up.
// Everything is a no-op when its target is absent, and nothing hides content
// when JS is off or Reduce Motion is on (the CSS guard owns the hidden state).
(function () {
  "use strict";

  // ---- 1. Popover demo tablist -------------------------------------------

  /**
   * @typedef {Object} PopoverDemo
   * @property {(index:number, focus?:boolean)=>void} select
   * @property {()=>void} init
   */
  function initPopoverDemo(root) {
    if (!root) return null;
    var tablist = root.querySelector('[role="tablist"]');
    var tabs = Array.prototype.slice.call(root.querySelectorAll('[role="tab"]'));
    if (!tablist || tabs.length === 0) return null;

    var panels = tabs.map(function (tab) {
      return document.getElementById(tab.getAttribute("aria-controls"));
    });

    // Lazy-load a panel's <img> (and its <picture><source>) on first activation.
    function loadPanelImage(panel) {
      if (!panel || panel.dataset.loaded === "1") return;
      panel.querySelectorAll("source[data-srcset]").forEach(function (s) {
        s.setAttribute("srcset", s.getAttribute("data-srcset"));
        s.removeAttribute("data-srcset");
      });
      panel.querySelectorAll("img[data-src]").forEach(function (img) {
        img.setAttribute("src", img.getAttribute("data-src"));
        img.removeAttribute("data-src");
      });
      panel.dataset.loaded = "1";
    }

    function select(index, focus) {
      if (index < 0) index = tabs.length - 1;
      if (index >= tabs.length) index = 0;
      tabs.forEach(function (tab, i) {
        var active = i === index;
        tab.setAttribute("aria-selected", active ? "true" : "false");
        tab.tabIndex = active ? 0 : -1;
        if (panels[i]) panels[i].hidden = !active;
      });
      loadPanelImage(panels[index]);
      if (focus) tabs[index].focus();
    }

    // Eagerly resolve the initially-selected panel's image.
    var initial = tabs.findIndex(function (t) {
      return t.getAttribute("aria-selected") === "true";
    });
    if (initial < 0) initial = 0;
    loadPanelImage(panels[initial]);

    tabs.forEach(function (tab, i) {
      tab.addEventListener("click", function () {
        select(i, true);
      });
    });

    tablist.addEventListener("keydown", function (e) {
      var current = tabs.findIndex(function (t) {
        return t.getAttribute("aria-selected") === "true";
      });
      if (current < 0) current = 0;
      var next = null;
      switch (e.key) {
        case "ArrowRight":
        case "ArrowDown":
          next = current + 1;
          break;
        case "ArrowLeft":
        case "ArrowUp":
          next = current - 1;
          break;
        case "Home":
          next = 0;
          break;
        case "End":
          next = tabs.length - 1;
          break;
        default:
          return;
      }
      e.preventDefault();
      select(next, true);
    });

    return { select: select, init: function () {} };
  }

  // ---- 2. Scroll reveal ---------------------------------------------------

  function initReveal() {
    var reduce =
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var targets = document.querySelectorAll(".reveal-init");
    if (!targets.length) return;
    // Under Reduce Motion the CSS start-state never applies, so content is
    // already visible — nothing to observe.
    if (reduce) return;
    if (!("IntersectionObserver" in window)) {
      targets.forEach(function (el) {
        el.classList.add("reveal-in");
      });
      return;
    }
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("reveal-in");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    targets.forEach(function (el) {
      io.observe(el);
    });
  }

  // ---- 3. Sticky CTA suppression -----------------------------------------

  function initStickyCta() {
    if (!document.querySelector("[data-sticky-cta]")) return;
    var suppressors = [].slice
      .call(document.querySelectorAll(".hero, #download"))
      .filter(Boolean);
    if (!suppressors.length || !("IntersectionObserver" in window)) return;
    var visible = new Set();
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) visible.add(entry.target);
          else visible.delete(entry.target);
        });
        if (visible.size) document.body.setAttribute("data-cta-hidden", "");
        else document.body.removeAttribute("data-cta-hidden");
      },
      { threshold: 0.15 }
    );
    suppressors.forEach(function (el) {
      io.observe(el);
    });
  }

  function boot() {
    document.querySelectorAll("[data-popover-demo]").forEach(initPopoverDemo);
    initReveal();
    initStickyCta();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

  // Expose for tests / debugging.
  window.initPopoverDemo = initPopoverDemo;
})();
