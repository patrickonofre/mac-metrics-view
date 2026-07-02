#!/usr/bin/env node
// build-en-page.mjs — generates the static English page docs/en/index.html from
// the Portuguese source of truth (docs/index.html) plus the `en` dictionary in
// docs/i18n.js. Run it whenever the layout or copy changes (e.g. every release).
//
// Why a generator: the EN page must be a real, crawlable URL (not a ?lang=
// swap), but hand-maintaining a second full HTML file drifts. This keeps the
// body (sections/cards/timeline) in lockstep with index.html and only the
// <head> here is EN-specific.
//
// Usage: node scripts/build-en-page.mjs
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);
const { STRINGS } = require(join(root, "docs/i18n.js"));
const en = STRINGS.en;

const SITE = "https://patrickonofre.github.io/mac-metrics-view";
const src = readFileSync(join(root, "docs/index.html"), "utf8");

const escHtml = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const escAttr = (s) => escHtml(s).replace(/"/g, "&quot;");

// --- 1. Extract the shared body and translate it to English ------------------
const bodyMatch = src.match(/<body[^>]*>([\s\S]*?)<\/body>/);
if (!bodyMatch) {
  console.error("✗ build-en-page: could not find <body> in docs/index.html");
  process.exit(1);
}
let body = bodyMatch[1];
const missing = [];

// Fill text nodes carrying data-i18n. These elements only ever contain text,
// so a lazy inner-capture up to the matching close tag is safe.
body = body.replace(
  /(<([a-zA-Z0-9]+)\b[^>]*\bdata-i18n="([^"]+)"[^>]*>)([\s\S]*?)(<\/\2>)/g,
  (m, open, _tag, key, _inner, close) => {
    if (!(key in en)) { missing.push(key); return m; }
    return open + escHtml(en[key]) + close;
  }
);

// Fill image alts carrying data-i18n-alt.
body = body.replace(/<img\b[^>]*\bdata-i18n-alt="([^"]+)"[^>]*>/g, (imgTag) => {
  const keyMatch = imgTag.match(/data-i18n-alt="([^"]+)"/);
  const key = keyMatch && keyMatch[1];
  if (!key || !(key in en)) { if (key) missing.push(key); return imgTag; }
  // Target the real alt attribute — the lookbehind avoids matching the "alt="
  // that lives inside data-i18n-alt, which would corrupt the key.
  return imgTag.replace(/(?<!-)\balt="[^"]*"/, `alt="${escAttr(en[key])}"`);
});

// Reflect the active language on the switch for the no-JS case (i18n.js also
// does this at runtime; baking it keeps the static page self-consistent).
body = body
  .replace(/(data-lang-option="pt"[^>]*?)aria-pressed="true"/, '$1aria-pressed="false"')
  .replace(/(data-lang-option="en"[^>]*?)aria-pressed="false"/, '$1aria-pressed="true"');

// The EN page sits one directory deeper, so rewrite root-relative asset paths.
body = body
  .replace(/\bsrc="assets\//g, 'src="../assets/')
  .replace(/\bdata-src="assets\//g, 'data-src="../assets/')
  .replace(/\bsrcset="assets\//g, 'srcset="../assets/')
  .replace(/\bdata-srcset="assets\//g, 'data-srcset="../assets/')
  .replace(/\bhref="downloads\//g, 'href="../downloads/');

if (missing.length) {
  console.error(`✗ build-en-page: ${missing.length} key(s) missing from en dict: ${[...new Set(missing)].join(", ")}`);
  process.exit(1);
}

// --- 2. Build the English <head> ---------------------------------------------
const faq = [
  ["Is Mac Metrics View free?", "Yes. It's free, open source, with no account and no in-app purchases."],
  ["Which Macs are supported?", "Macs with Apple Silicon (M1 chip or later) running macOS 14 (Sonoma) or later. Version 2.2 was the last to support Intel Macs."],
  ["Does the app collect my data?", "No. Every metric read is local — no telemetry, no account, and nothing sent over the network."],
  ["How do I open the app the first time?", "Because the app isn't notarized yet, on first launch right-click the icon and choose Open to confirm. After that it opens normally and keeps itself up to date."],
  ["Does Mac Metrics View update itself?", "Yes. New versions are downloaded and installed with your confirmation via Sparkle, without downloading the app again."],
];

const head = `  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <!-- Progressive-enhancement marker: scroll-reveal start-state is gated on
         html.js so content is never stuck hidden when JS is absent. -->
    <script>document.documentElement.classList.add("js");</script>
    <title>Mac Metrics View — CPU, GPU and RAM in the macOS menu bar</title>
    <meta name="description" content="CPU, GPU, memory, network, temperature, disk, battery, and AI tokens in the macOS menu bar. Native, free, open-source app — 100% local, no telemetry.">
    <link rel="canonical" href="${SITE}/en/">
    <link rel="alternate" hreflang="pt-br" href="${SITE}/">
    <link rel="alternate" hreflang="en" href="${SITE}/en/">
    <link rel="alternate" hreflang="x-default" href="${SITE}/">
    <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">
    <meta name="author" content="Patrick Onofre">
    <meta name="theme-color" content="#0b0c10" media="(prefers-color-scheme: dark)">
    <meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">

    <!-- Open Graph -->
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="Mac Metrics View">
    <meta property="og:url" content="${SITE}/en/">
    <meta property="og:title" content="Mac Metrics View 2.5 — your Mac's metrics in the menu bar">
    <meta property="og:description" content="CPU, GPU, RAM, network, temperature, disk, battery, and AI tokens right in the macOS menu bar. Native, local, and telemetry-free.">
    <meta property="og:image" content="${SITE}/assets/popover-cpu-light.png">
    <meta property="og:image:alt" content="Mac Metrics View 2.0 popover on the CPU tab, showing current usage and the top processes">
    <meta property="og:image:width" content="680">
    <meta property="og:image:height" content="860">
    <meta property="og:locale" content="en_US">
    <meta property="og:locale:alternate" content="pt_BR">

    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="Mac Metrics View 2.5 — your Mac's metrics in the menu bar">
    <meta name="twitter:description" content="CPU, GPU, RAM, network, temperature, disk, battery, and AI tokens right in the macOS menu bar. Native, local, and telemetry-free.">
    <meta name="twitter:image" content="${SITE}/assets/popover-cpu-light.png">

    <link rel="icon" href="../assets/app-icon.png">
    <link rel="apple-touch-icon" href="../assets/app-icon.png">
    <link rel="stylesheet" href="../styles.css">
    <script src="../i18n.js" defer></script>
    <script src="../popover-demo.js" defer></script>

    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      "name": "Mac Metrics View",
      "operatingSystem": "macOS 14+",
      "applicationCategory": "UtilitiesApplication",
      "processorRequirements": "Apple Silicon (M1 or later)",
      "description": "Native macOS app that shows CPU, GPU, memory, network, temperature, disk, battery, and AI tokens (Claude Code and Codex) right in the menu bar. Local reads, no account, no telemetry.",
      "url": "${SITE}/en/",
      "softwareVersion": "2.5.0",
      "datePublished": "2026-05-26",
      "dateModified": "2026-07-02",
      "fileSize": "2MB",
      "image": "${SITE}/assets/popover-cpu-light.png",
      "screenshot": "${SITE}/assets/popover-cpu-light.png",
      "inLanguage": ["en", "pt-BR"],
      "downloadUrl": "${SITE}/downloads/MacMetricsView-2.5.0.zip",
      "installUrl": "${SITE}/en/#download",
      "releaseNotes": "${SITE}/en/#timeline",
      "sameAs": "https://github.com/patrickonofre/mac-metrics-view",
      "isAccessibleForFree": true,
      "author": {
        "@type": "Person",
        "name": "Patrick Onofre",
        "url": "https://github.com/patrickonofre"
      },
      "offers": {
        "@type": "Offer",
        "price": "0",
        "priceCurrency": "USD"
      }
    }
    </script>

    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      "inLanguage": "en",
      "mainEntity": [
${faq
  .map(
    ([q, a]) => `        {
          "@type": "Question",
          "name": ${JSON.stringify(q)},
          "acceptedAnswer": {
            "@type": "Answer",
            "text": ${JSON.stringify(a)}
          }
        }`
  )
  .join(",\n")}
      ]
    }
    </script>
  </head>`;

// --- 3. Assemble and write ---------------------------------------------------
const out = `<!doctype html>
<html lang="en">
${head}
  <body>${body}</body>
</html>
`;

mkdirSync(join(root, "docs/en"), { recursive: true });
writeFileSync(join(root, "docs/en/index.html"), out, "utf8");
console.log("✓ build-en-page OK — wrote docs/en/index.html (body synced from index.html, en head baked).");
