#!/usr/bin/env bash
# Records every promo shot (tests/promo.gd) and cuts each movie down to its clip.
#
#   node scripts/stage-preview.js all .preview
#   bash luau/gdextension/demo2/tests/promo.sh <out dir> [shot ...]
#
# Every run is a take of its own: <out>/take-<month><day>-<hour><minute>/clips/<shot>.mp4 (1920x1080,
# 60 fps, with the town's sound) and .../stills/*.png. Nothing already shot is ever written over --
# a take somebody liked is not there to be re-made, however bad the one after it turned out.
# Needs ffmpeg, and a screen the 1920x1080 window fits on. Do not play while it runs: each shot is
# a whole town drawn flat out.
set -u
GODOT="${GODOT:-C:/tools/godot/Godot_v4.3-stable_win64_console.exe}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: promo.sh <out dir> [shot ...]}"; shift || true
SHOTS=("$@"); [ ${#SHOTS[@]} -eq 0 ] && SHOTS=(arrival flyover tree earth fires outfit cast spoon pets fish walk)
OUT="$OUT/take-$(date +%m%d-%H%M)"
mkdir -p "$OUT/clips" "$OUT/stills"
echo "take: $OUT"
OUTW="$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")"
cd "$HERE"
for shot in "${SHOTS[@]}"; do
  raw="$OUTW/clips/_$shot.avi"
  log="$("$GODOT" --path . --write-movie "$raw" --fixed-fps 60 --resolution 1920x1080 -s res://tests/promo.gd -- "$shot" "$OUTW/stills" 2>&1)"
  echo "$log" | grep -E "PROMO |LUA ERROR|SCRIPT ERROR" | head -40
  clip="$(echo "$log" | grep -E "^CLIP " | tail -1)"
  if [ -z "$clip" ]; then echo "$shot: no CLIP line, skipped"; continue; fi
  first="$(echo "$clip" | awk '{print $2}')"; last="$(echo "$clip" | awk '{print $3}')"
  ffmpeg -v error -y -i "$raw" -ss "$(awk "BEGIN{print $first/60}")" -to "$(awk "BEGIN{print $last/60}")" \
    -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -c:a aac -b:a 192k "$OUTW/clips/$shot.mp4" \
    && rm -f "$raw" && echo "$shot: $(awk "BEGIN{printf \"%.1f\", ($last-$first)/60}") s -> $OUTW/clips/$shot.mp4"
done
