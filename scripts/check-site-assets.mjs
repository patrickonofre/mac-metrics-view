#!/usr/bin/env node
// check-site-assets.mjs — validates the 2.0 marketing-site image assets against
// scripts/site-assets-manifest.json. Acts as the asset gate for task_01:
//   • every expected file exists (1 menu-bar + 8 popover PNGs)
//   • each popover tab has BOTH a -light and -dark variant (no missing theme)
//   • each PNG's pixel size matches the manifest (logical points or exact 2x)
//   • each PNG is under its byte budget
//   • the demo panels in docs/index.html reference no 1.x asset filename
// Exit non-zero on any failure so it can run in CI / as a release gate.
//
// Usage: node scripts/check-site-assets.mjs
import { readFileSync, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(
  readFileSync(join(root, "scripts/site-assets-manifest.json"), "utf8"),
);
const assetsDir = join(root, manifest.assetsDir);
const indexPath = join(root, "docs/index.html");

const failures = [];
const fail = (m) => failures.push(m);

// Parse a PNG's IHDR for [width, height]. Returns null if not a valid PNG.
function pngSize(path) {
  const buf = readFileSync(path);
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (buf.length < 24 || !buf.subarray(0, 8).equals(sig)) return null;
  if (buf.subarray(12, 16).toString("ascii") !== "IHDR") return null;
  return [buf.readUInt32BE(16), buf.readUInt32BE(20)];
}

// A file passes dimension check at logical (1x) OR exact-double (2x) size.
function checkImage(file, wantW, wantH, budgetKB) {
  const path = join(assetsDir, file);
  if (!existsSync(path)) {
    fail(`MISSING: ${manifest.assetsDir}/${file}`);
    return;
  }
  const kb = statSync(path).size / 1024;
  if (kb > budgetKB) {
    fail(`OVER BUDGET: ${file} is ${kb.toFixed(0)}KB (budget ${budgetKB}KB)`);
  }
  const size = pngSize(path);
  if (!size) {
    fail(`NOT A VALID PNG: ${file}`);
    return;
  }
  const [w, h] = size;
  const ok1x = w === wantW && h === wantH;
  const ok2x = w === wantW * 2 && h === wantH * 2;
  if (!ok1x && !ok2x) {
    fail(
      `BAD DIMENSIONS: ${file} is ${w}x${h}, expected ${wantW}x${wantH} (or 2x ${wantW * 2}x${wantH * 2})`,
    );
  }
}

// 1. Menu-bar hero strip.
checkImage(
  manifest.menuBar.file,
  manifest.menuBar.width,
  manifest.menuBar.height,
  manifest.byteBudgetKB.menuBar,
);

// 2. Each popover tab in both themes (presence + pairing + dims + budget).
for (const tab of manifest.tabs) {
  for (const theme of ["light", "dark"]) {
    const file = tab[theme];
    if (!file) {
      fail(`MISSING THEME: tab "${tab.id}" has no ${theme} variant`);
      continue;
    }
    checkImage(
      file,
      manifest.popoverWidth,
      manifest.popoverHeight,
      manifest.byteBudgetKB.popover,
    );
  }
}

// 3. No 1.x demo asset filename referenced by a popover demo panel.
if (existsSync(indexPath)) {
  const html = readFileSync(indexPath, "utf8");
  const panelImgs = [...html.matchAll(/role="tabpanel"[\s\S]*?<\/[^>]*>/g)]
    .join("\n");
  for (const legacy of manifest.legacyDemoAssetsForbidden) {
    if (panelImgs.includes(legacy)) {
      fail(`LEGACY ASSET IN DEMO PANEL: ${legacy} referenced inside a tabpanel`);
    }
  }
}

if (failures.length) {
  console.error(`✗ site-assets check FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(
  `✓ site-assets OK — 1 menu-bar + ${manifest.tabs.length * 2} popover PNGs present, sized, and within budget.`,
);
