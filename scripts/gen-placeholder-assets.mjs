#!/usr/bin/env node
// gen-placeholder-assets.mjs — DEV ONLY. Generates solid-color placeholder PNGs
// at the manifest's logical dimensions so the redesigned site renders and can be
// verified in a browser preview BEFORE the real 2.0 captures exist. These are NOT
// shipping assets — replace them with real captures via capture-site-screenshots.sh.
// Light/dark variants use distinct tints so the per-theme swap is visually verifiable.
import { deflateSync } from "node:zlib";
import { writeFileSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const m = JSON.parse(readFileSync(join(root, "scripts/site-assets-manifest.json"), "utf8"));
const dir = join(root, m.assetsDir);

const crcTable = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, "ascii");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}
function solidPng(w, h, [r, g, b]) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; // 8-bit, RGB
  const row = Buffer.alloc(1 + w * 3);
  for (let x = 0; x < w; x++) { row[1 + x * 3] = r; row[2 + x * 3] = g; row[3 + x * 3] = b; }
  const raw = Buffer.concat(Array.from({ length: h }, () => row));
  return Buffer.concat([sig, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

const tint = {
  cpu:     { light: [0xe8, 0xf0, 0xff], dark: [0x10, 0x1a, 0x2c] },
  ram:     { light: [0xe8, 0xfb, 0xee], dark: [0x10, 0x24, 0x18] },
  netdisk: { light: [0xfb, 0xf0, 0xe6], dark: [0x24, 0x18, 0x10] },
  ai:      { light: [0xf2, 0xe8, 0xfb], dark: [0x1c, 0x12, 0x28] },
};

writeFileSync(join(dir, m.menuBar.file), solidPng(m.menuBar.width, m.menuBar.height, [0x0b, 0x0b, 0x1f]));
for (const tab of m.tabs) {
  for (const theme of ["light", "dark"]) {
    writeFileSync(join(dir, tab[theme]), solidPng(m.popoverWidth, m.popoverHeight, tint[tab.id][theme]));
  }
}
console.log(`(dev) wrote ${1 + m.tabs.length * 2} placeholder PNGs to ${m.assetsDir}/ — replace with real captures.`);
