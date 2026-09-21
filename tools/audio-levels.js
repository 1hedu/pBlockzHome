// Peak and RMS per WAV for the town's sounds, and --fix to level the effects to one RMS.
// Reads WAV only: PCM 8/16/24/32-bit and float.
//
//   node scripts/audio-levels.js [dir]...   defaults to scripts/sfx
//   --fix     rewrite the effects in place at TARGET_RMS_DB; instruments untouched
//   --all     count the instrument sources in the spread report too
//   --check   exit 1 on clipping, peaks past CEILING, or spread past MAX_SPREAD_DB
const fs = require("fs"), path = require("path");

// Floor of the RMS window, relative to the clip's OWN peak. An absolute floor moves the
// window when the gain does, so a set levelled to one number re-measures dB apart.
const SILENCE_BELOW_PEAK_DB = -40;

// RMS, not peak: peak normalisation leaves a short click and a long chord "both at 0 dB" and
// sounding nothing alike.
const TARGET_RMS_DB = -18;
const CEILING = 0.89;            // -1 dBFS, headroom for the master limiter in host/Audio.gd
const MAX_SPREAD_DB = 3;         // tolerance for a clip meant to sit apart, not a measuring margin

// nes-* are NesEngine's oscillator sources, not effects: the engine gains them per note
// (ch.volume * master) on the Music group, and a full-range square reads -3.5 dB rms.
const INSTRUMENTS = /^nes-/i;
const db = (x) => (x <= 0 ? -Infinity : 20 * Math.log10(x));
const show = (x) => (x === -Infinity ? "  -inf" : (x >= 0 ? "+" : "") + x.toFixed(1));

/** Channels interleaved as floats in [-1, 1], plus the fmt chunk; null if not a WAV this reads. */
function samples(buf) {
  if (buf.length < 44 || buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WAVE") return null;
  let fmt = null, data = null, at = 12;
  while (at + 8 <= buf.length) {
    const id = buf.toString("ascii", at, at + 4);
    const size = buf.readUInt32LE(at + 4);
    const body = buf.subarray(at + 8, at + 8 + size);
    if (id === "fmt ") fmt = { format: body.readUInt16LE(0), channels: body.readUInt16LE(2), rate: body.readUInt32LE(4), bits: body.readUInt16LE(14) };
    else if (id === "data") data = body;
    at += 8 + size + (size % 2);       // RIFF chunks are word-aligned; an odd size carries a pad byte
  }
  if (!fmt || !data) return null;

  const { format, bits } = fmt;
  const out = [];
  if (format === 3 && bits === 32) { for (let i = 0; i + 4 <= data.length; i += 4) out.push(data.readFloatLE(i)); }
  else if (format === 1 && bits === 16) { for (let i = 0; i + 2 <= data.length; i += 2) out.push(data.readInt16LE(i) / 32768); }
  else if (format === 1 && bits === 8) { for (let i = 0; i < data.length; i++) out.push((data[i] - 128) / 128); }
  else if (format === 1 && bits === 24) { for (let i = 0; i + 3 <= data.length; i += 3) { const v = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16); out.push((v & 0x800000 ? v - 0x1000000 : v) / 8388608); } }
  else if (format === 1 && bits === 32) { for (let i = 0; i + 4 <= data.length; i += 4) out.push(data.readInt32LE(i) / 2147483648); }
  else return null;
  return { fmt, data: out };
}

function measure(buf) {
  const got = samples(buf);
  if (!got) return null;
  const s = got.data;
  let peak = 0, clipped = 0;
  for (const v of s) {
    const a = Math.abs(v);
    if (a > peak) peak = a;
    // At full scale the source file was already wrapped: turning it down here, or limiting it
    // downstream, cannot unfold the waveform -- clipping is a failure --fix cannot repair.
    if (a >= 0.999) clipped++;
  }
  const floor = peak * Math.pow(10, SILENCE_BELOW_PEAK_DB / 20);
  // RMS spans the first to the last sounding sample only: a long tail averaged in reads as a
  // quiet clip and has --fix boost it.
  let from = 0, to = s.length - 1;
  while (from < s.length && Math.abs(s[from]) < floor) from++;
  while (to > from && Math.abs(s[to]) < floor) to--;
  let sum = 0;
  for (let i = from; i <= to; i++) sum += s[i] * s[i];
  const n = Math.max(1, to - from + 1);
  return {
    peak, rms: Math.sqrt(sum / n), clipped,
    seconds: s.length / (got.fmt.channels * got.fmt.rate),
    sounding: n / (got.fmt.channels * got.fmt.rate),
    fmt: got.fmt, samples: s,
  };
}

function main() {
  const fix = process.argv.includes("--fix");
  const all = process.argv.includes("--all");
  const check = process.argv.includes("--check");
  const dirs = process.argv.slice(2).filter((a) => !a.startsWith("--"));
  const roots = dirs.length ? dirs : [path.join(__dirname, "sfx")];

  const rows = [];
  for (const root of roots) {
    for (const f of fs.readdirSync(root).filter((f) => f.toLowerCase().endsWith(".wav")).sort()) {
      const file = path.join(root, f);
      const m = measure(fs.readFileSync(file));
      if (!m) { console.log(`${f.padEnd(20)} not a wav this reads`); continue; }
      rows.push({ f, file, ...m });
    }
  }
  if (rows.length === 0) { console.log("nothing to measure"); return; }

  const effects = rows.filter((r) => !INSTRUMENTS.test(r.f));
  const instruments = rows.filter((r) => INSTRUMENTS.test(r.f));

  const table = (what, list) => {
    if (list.length === 0) return;
    console.log(`\n${what}`);
    console.log("file                  peak dB   rms dB   sounding   clipped");
    for (const r of list) {
      const flag = r.clipped > 0 ? `  <-- ${r.clipped} sample(s) at full scale` : "";
      console.log(`${r.f.padEnd(20)} ${show(db(r.peak)).padStart(7)}  ${show(db(r.rms)).padStart(7)}   ${r.sounding.toFixed(2)}s${flag}`);
    }
  };
  table("EFFECTS", effects);
  table("INSTRUMENT SOURCES (the engine sets these; --fix leaves them alone)", instruments);

  // Spread between the loudest and quietest rms, which is what the ear notices: +10 dB is
  // about twice as loud.
  const judge = all ? rows : effects;
  const rmss = judge.map((r) => db(r.rms)).filter((x) => x !== -Infinity);
  const loudest = judge.reduce((a, b) => (b.rms > a.rms ? b : a));
  const quietest = judge.reduce((a, b) => (b.rms < a.rms ? b : a));
  const median = rmss.slice().sort((a, b) => a - b)[Math.floor(rmss.length / 2)];
  console.log(`\n${judge.length} effect(s)`);
  console.log(`loudest  : ${loudest.f} at ${show(db(loudest.rms))} dB rms`);
  console.log(`quietest : ${quietest.f} at ${show(db(quietest.rms))} dB rms`);
  console.log(`spread   : ${(db(loudest.rms) - db(quietest.rms)).toFixed(1)} dB, median ${show(median)} dB`);
  const hot = rows.filter((r) => r.clipped > 0);
  console.log(`clipping : ${hot.length ? hot.map((r) => r.f).join(", ") : "none -- nothing reaches full scale"}`);

  if (check) {
    const spread = db(loudest.rms) - db(quietest.rms);
    const loud = rows.filter((r) => r.peak > CEILING);
    const bad = [];
    if (hot.length) bad.push(`${hot.length} clipping: ${hot.map((r) => r.f).join(", ")}`);
    if (loud.length) bad.push(`${loud.length} past the ${show(db(CEILING))} dB ceiling: ${loud.map((r) => r.f).join(", ")}`);
    if (spread > MAX_SPREAD_DB) bad.push(`effects span ${spread.toFixed(1)} dB, more than ${MAX_SPREAD_DB}`);
    console.log(bad.length
      ? "\naudio levels: FAIL\n  " + bad.join("\n  ") + "\n\nnode scripts/audio-levels.js --fix levels them."
      : "\naudio levels: PASS");
    process.exitCode = bad.length ? 1 : 0;
    return;
  }

  if (!fix) return;
  rows.length = 0;
  rows.push(...effects);
  // Every file is rewritten as 16-bit PCM, whatever format it came in as; git is the undo.
  console.log(`\nlevelling in place: ${TARGET_RMS_DB} dB rms, never past ${show(db(CEILING))} dB peak`);
  console.log("(the deliberate offsets stay in the town -- UI clicks play at Volume 0.55, under the fight)");
  for (const r of rows) {
    if (r.rms <= 0) { console.log(`${r.f.padEnd(20)} silent, left alone`); continue; }
    let gain = Math.pow(10, TARGET_RMS_DB / 20) / r.rms;
    const held = r.peak * gain > CEILING;
    if (held) gain = CEILING / r.peak;
    const out = Buffer.alloc(44 + r.samples.length * 2);
    out.write("RIFF", 0, "ascii"); out.writeUInt32LE(36 + r.samples.length * 2, 4); out.write("WAVE", 8, "ascii");
    out.write("fmt ", 12, "ascii"); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20);
    out.writeUInt16LE(r.fmt.channels, 22); out.writeUInt32LE(r.fmt.rate, 24);
    out.writeUInt32LE(r.fmt.rate * r.fmt.channels * 2, 28); out.writeUInt16LE(r.fmt.channels * 2, 32); out.writeUInt16LE(16, 34);
    out.write("data", 36, "ascii"); out.writeUInt32LE(r.samples.length * 2, 40);
    for (let i = 0; i < r.samples.length; i++) {
      const v = Math.max(-1, Math.min(1, r.samples[i] * gain));
      out.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
    }
    fs.writeFileSync(r.file, out);
    console.log(`${r.f.padEnd(20)} ${show(20 * Math.log10(gain)).padStart(7)} dB${held ? "  (held at the ceiling)" : ""}`);
  }
}

main();
