// The title card, shrunk to something a chain can carry.
//
//   node scripts/prep-splash.js [source.png]
//
// Every byte published costs gas, and the source art is 1536 x 1024 and two megabytes. The
// aspect is kept, not cropped to a window: the card is drawn to fill whatever screen it lands
// on, and the overflow is lost off the sides.
const fs = require("fs");
const path = require("path");
const { Canvas, decode, encode, blit } = require("./png");

const SRC = process.argv[2] || process.env.SPLASH_SRC || "";
if (!SRC) {
  console.error("usage: node scripts/prep-splash.js <source.png>   (or set SPLASH_SRC)");
  process.exit(1);
}
const OUT = path.join(__dirname, "models", "splash.png");
// The card sits behind a fade for a few seconds, so softness costs nothing.
const WIDTH = 512;

// Photographs do not deflate. Dropping the low two bits of each channel gives the compressor
// long runs and takes the encode from about a megabyte down to a third of one, invisibly
// behind a fade; the | 2 re-centres a value in the range it now stands for, so the image does
// not darken.
function posterise(c) {
  for (let i = 0; i < c.px.length; i += 4)
    for (let k = 0; k < 3; k++) c.px[i + k] = (c.px[i + k] & 0xfc) | 2;
}

const src = decode(fs.readFileSync(SRC));
const height = Math.round((src.h / src.w) * WIDTH);
const out = new Canvas(WIDTH, height);
blit(out, src, 0, 0, WIDTH, height);
posterise(out);
const png = encode(out.px, out.w, out.h);
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, png);
console.log("splash.png  %dx%d -> %dx%d, %s bytes (was %s)",
  src.w, src.h, WIDTH, height, png.length.toLocaleString(),
  fs.statSync(SRC).size.toLocaleString());
