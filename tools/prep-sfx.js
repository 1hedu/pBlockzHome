// Decodes the UI sound clips to 16-bit PCM WAV; the results are committed.
//
//   node scripts/prep-sfx.js [srcDir]
//
// Godot's WAV importer takes PCM and IMA-ADPCM only, and imports MS-ADPCM (WAVE tag 2) as
// silence rather than failing.
const fs = require("fs");
const path = require("path");

// The raw clips live outside the checkout: pass the folder, or set SFX_SRC
const SRC = process.argv[2] || process.env.SFX_SRC || path.join(__dirname, "..", "..");
const OUT = path.join(__dirname, "sfx");

// MS-ADPCM's fixed adaptation table, indexed by nibble; the predictor pairs come from fmt
const ADAPT = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230];
const clamp16 = (v) => (v < -32768 ? -32768 : v > 32767 ? 32767 : v);
const nib = (n) => (n & 8 ? n - 16 : n);           // the nibble is signed

function chunks(buf) {
  const out = {};
  let i = 12;
  while (i + 8 <= buf.length) {
    const id = buf.toString("ascii", i, i + 4);
    const size = buf.readUInt32LE(i + 4);
    out[id] = buf.subarray(i + 8, i + 8 + size);
    i += 8 + size + (size & 1);
  }
  return out;
}

function decodeMsAdpcm(buf) {
  const c = chunks(buf);
  if (!c["fmt "] || !c.data) throw new Error("not a RIFF/WAVE file");
  const fmt = c["fmt "];
  const tag = fmt.readUInt16LE(0);
  const channels = fmt.readUInt16LE(2);
  const rate = fmt.readUInt32LE(4);
  const blockAlign = fmt.readUInt16LE(12);
  const bits = fmt.readUInt16LE(14);
  // 8-bit WAV samples are unsigned with 128 as zero; the writer below only emits 16-bit.
  // Of the eighteen sources only the cane's two, charge and buster, are 8-bit
  if (tag === 1 && bits === 16) return { pcm: c.data, rate, channels, already: true };
  if (tag === 1 && bits === 8) {
    const pcm = Buffer.alloc(c.data.length * 2);
    for (let k = 0; k < c.data.length; k++) pcm.writeInt16LE((c.data[k] - 128) * 256, k * 2);
    return { pcm, rate, channels, already: true };
  }
  if (tag === 1) throw new Error(`unsupported PCM depth ${bits}`);
  if (tag !== 2) throw new Error(`unsupported WAVE format ${tag}`);

  const samplesPerBlock = fmt.readUInt16LE(18);
  const numCoef = fmt.readUInt16LE(20);
  const coef = [];
  for (let k = 0; k < numCoef; k++)
    coef.push([fmt.readInt16LE(22 + k * 4), fmt.readInt16LE(24 + k * 4)]);

  const data = c.data;
  const out = [];
  for (let off = 0; off + blockAlign <= data.length; off += blockAlign) {
    const b = data.subarray(off, off + blockAlign);
    let p = 0;
    const pred = [], delta = [], s1 = [], s2 = [];
    for (let ch = 0; ch < channels; ch++) pred[ch] = Math.min(b[p++], numCoef - 1);
    for (let ch = 0; ch < channels; ch++) { delta[ch] = b.readInt16LE(p); p += 2; }
    for (let ch = 0; ch < channels; ch++) { s1[ch] = b.readInt16LE(p); p += 2; }
    for (let ch = 0; ch < channels; ch++) { s2[ch] = b.readInt16LE(p); p += 2; }
    // The block header's priming samples are real output; s2 is the earlier one
    for (let ch = 0; ch < channels; ch++) out.push(s2[ch]);
    for (let ch = 0; ch < channels; ch++) out.push(s1[ch]);

    const step = (ch, n) => {
      const [c1, c2] = coef[pred[ch]];
      let v = Math.floor((s1[ch] * c1 + s2[ch] * c2) / 256) + nib(n) * delta[ch];
      v = clamp16(v);
      s2[ch] = s1[ch];
      s1[ch] = v;
      delta[ch] = Math.max(16, Math.floor((ADAPT[n] * delta[ch]) / 256));
      return v;
    };
    for (let i = 2; i < samplesPerBlock && p < b.length; i++) {
      const byte = b[p++];
      out.push(step(0, byte >> 4));
      out.push(step(channels > 1 ? 1 : 0, byte & 15));
    }
  }
  const pcm = Buffer.alloc(out.length * 2);
  out.forEach((v, i) => pcm.writeInt16LE(clamp16(v), i * 2));
  return { pcm, rate, channels };
}

function wav(pcm, rate, channels) {
  const head = Buffer.alloc(44);
  head.write("RIFF", 0);
  head.writeUInt32LE(36 + pcm.length, 4);
  head.write("WAVEfmt ", 8);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(1, 20);                       // PCM
  head.writeUInt16LE(channels, 22);
  head.writeUInt32LE(rate, 24);
  head.writeUInt32LE(rate * channels * 2, 28);
  head.writeUInt16LE(channels * 2, 32);
  head.writeUInt16LE(16, 34);
  head.write("data", 36);
  head.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([head, pcm]);
}

// Keys are roles; callers never name a file. Combat names are from the listener's side: one
// swing is `enemyhit` to whoever landed it and `hurt` to whoever took it.
const CLIPS = {
  menu: "000.wav",
  item: "001.wav",
  sword1: "fighter sword 1.wav",
  sword2: "fighter sword 2.wav",
  master: "master sword.wav",
  fire: "fire.wav",
  enemyhit: "enemy hit.wav",
  enemydies: "enemy dies.wav",
  // A jump attack: both ends hear this instead of the enemyhit/hurt pair
  stronghit: "Strong Hit.wav",
  hurt: "link hurt.wav",
  dies: "link dies.wav",
  lowhp: "low hp.wav",
  fall: "fall.wav",
  // The Familiar's two lines, played alternately
  familiar1: "WARC_SE_345.wav",
  familiar2: "WARC_SE_365.wav",
  // The roof trampolines: heard by everyone near the pad, not only whoever bounced
  trampoline: "S1_CC.wav",
  // The cane: charge, played at a sixth speed while held, and shot, pitched down by charge time
  charge: "28 - VanishingBlocks.wav",
  buster: "05 - MegaBuster.wav",
};

fs.mkdirSync(OUT, { recursive: true });
// Clips reshaped after decoding, by role.
//
// The charge has to fill six seconds at a sixth speed, but the 0.88s file is audible only to
// about 0.8s. So: 0 to 2/3s of the file, then 1/3 to 2/3s again, crossfaded over 10ms so the
// jump back does not click.
const RESHAPE = {
  charge: (pcm, rate, channels) => {
    const frame = 2 * channels;
    const at = (secs) => Math.round(secs * rate) * frame;
    const fade = Math.round(0.01 * rate);
    // The head runs one fade long, so the overlap comes out of it and not the six seconds
    const head = pcm.subarray(0, at(4 / 6) + fade * frame);
    const again = Buffer.from(pcm.subarray(at(2 / 6), at(4 / 6)));
    const tail = head.length - fade * frame;
    for (let k = 0; k < fade; k++) {
      const u = (k + 0.5) / fade;
      for (let ch = 0; ch < channels; ch++) {
        const i = k * frame + ch * 2;
        const mixed = head.readInt16LE(tail + ch * 2 + k * frame) * (1 - u) + again.readInt16LE(i) * u;
        again.writeInt16LE(clamp16(Math.round(mixed)), i);
      }
    }
    return Buffer.concat([head.subarray(0, tail), again]);
  },
};

for (const [role, file] of Object.entries(CLIPS)) {
  const src = path.join(SRC, file);
  if (!fs.existsSync(src)) {
    console.error(`missing ${src}`);
    process.exitCode = 1;
    continue;
  }
  const raw = fs.readFileSync(src);
  const decoded = decodeMsAdpcm(raw);
  const { rate, channels, already } = decoded;
  const pcm = RESHAPE[role] ? RESHAPE[role](decoded.pcm, rate, channels) : decoded.pcm;
  const outFile = path.join(OUT, `${role}.wav`);
  fs.writeFileSync(outFile, wav(pcm, rate, channels));
  const secs = pcm.length / 2 / channels / rate;
  console.log(`${role.padEnd(5)} ${file}  ${String(raw.length).padStart(5)} B ` +
    `${already ? "(already PCM)" : "MS-ADPCM"} -> ${String(pcm.length + 44).padStart(6)} B PCM16, ` +
    `${channels}ch ${rate}Hz, ${secs.toFixed(3)}s`);
}
console.log(`\nwrote ${OUT}`);
