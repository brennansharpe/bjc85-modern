#!/usr/bin/env node
// Rasterize the editable SVGs for GitHub and create a convenient contact sheet.
// Requires sharp 0.35.4 (npm install --prefix /tmp/bjc85-presentation sharp@0.35.4).
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../..');
const directory = path.join(root, 'docs/images');

async function main() {
  const shots = JSON.parse(await fs.readFile(path.join(directory, 'manifest.json'), 'utf8'));
  for (const shot of shots) {
    await sharp(path.join(directory, shot.file), { density: 144 })
      .png({ compressionLevel: 9 }).toFile(path.join(directory, shot.png));
  }
  const tiles = await Promise.all(shots.map(async (shot, i) => ({
    input: await sharp(path.join(directory, shot.png)).resize(900, 675).toBuffer(),
    left: (i % 2) * 900, top: Math.floor(i / 2) * 675,
  })));
  await sharp({ create: { width: 1800, height: 2025, channels: 3, background: '#eef1f5' } })
    .composite(tiles).png({ compressionLevel: 9 }).toFile(path.join(directory, 'gallery.png'));
  console.log(`Rendered ${shots.length} PNGs at 2880 × 2160, plus gallery.png.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
