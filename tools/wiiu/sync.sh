#!/usr/bin/env bash
# Pulls everything the Android game needs out of the Wii U game (seanmallan316/kingdomkart):
# roads, characters, karts, cups, story map, pictures, 3D models, music, sounds, voices and the opening cutscene.
# Usage: tools/wiiu/sync.sh <path to the Wii U repo>
set -euo pipefail
WIIU=$(cd "$1" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
GAME=$ROOT/game
WORK=$(mktemp -d)

# 1. the data, read straight from the Wii U code
{ grep -E '^#define (SM_NODES|SM_W|SM_D|SM_HS) ' "$WIIU/src/game/storymode.h"
  sed -n '/^typedef struct { const char \*name; float px, py; int track; const char \*verse; } SmNode;/,/^typedef char sm_one_trip_each/p' \
  "$WIIU/src/game/storymode.h" | grep -v '^typedef char sm_one_trip_each'; } > "$WORK/gen_story.h"
grep -q 'SM_NODE\[' "$WORK/gen_story.h"
{ grep -m1 '^#define NUM_GP_ROUNDS_MAX' "$WIIU/src/game/view.c"
  grep -m1 '^typedef struct { const char \*name, \*sub; int roads' "$WIIU/src/game/view.c"
  grep -m1 '^#define NCUPS' "$WIIU/src/game/view.c"
  sed -n '/^static const Cup CUPS\[NCUPS\]/,/};/p' "$WIIU/src/game/view.c"; } > "$WORK/gen_cups.h"
grep -q 'CUPS\[NCUPS\]' "$WORK/gen_cups.h"
SIM=$(ls "$WIIU"/src/sim/*.c)
gcc -O1 -w -o "$WORK/export" -I"$WIIU/src" -I"$WORK" "$HERE/export.c" "$WIIU/src/world/track.c" "$WIIU/src/world/tracks.c" \
  $SIM "$WIIU/src/game/save.c" -lm
mkdir -p "$GAME/data"
"$WORK/export" "$GAME/data"

# 2. pictures, music, sounds, voices, the opening cutscene
mkdir -p "$GAME/img" "$GAME/music" "$GAME/sfx" "$GAME/video" "$GAME/models"
cp "$WIIU"/content/img/*.png "$GAME/img/"
cp "$WIIU"/content/music/*.mp3 "$GAME/music/"
cp "$WIIU"/content/sfx/*.wav "$GAME/sfx/"
cp "$WIIU"/content/sfx/*.lip "$GAME/sfx/" 2>/dev/null || true
[ -f "$WIIU/content/img/story_map.png" ] && cp "$WIIU/content/img/story_map.png" "$GAME/img/"
if [ ! -f "$GAME/video/opener.ogv" ] || [ "$WIIU/content/video/opener_000.jpg" -nt "$GAME/video/opener.ogv" ]; then
  ffmpeg -nostdin -y -v error -framerate 24 -i "$WIIU/content/video/opener_%03d.jpg" -i "$WIIU/content/music/music_opener.mp3" \
    -c:v libtheora -q:v 8 -c:a libvorbis -q:a 6 -shortest -pix_fmt yuv420p "$GAME/video/opener.ogv"
fi

# 3. every 3D model (characters with their karts, props, the whale, Goliath)
for m in "$WIIU"/content/models/*.kkm; do
  b=$(basename "$m" .kkm)
  case "$b" in *_lo) continue;; esac
  png="$WIIU/content/models/$b.png"
  [ -f "$png" ] || continue
  python3 -I "$ROOT/tools/kkm2glb.py" "$m" "$png" "$GAME/models/$b.glb" > /dev/null
done
cp "$WIIU"/content/models/*.face "$GAME/models/" 2>/dev/null || true
echo "Wii U sync done: $(ls "$GAME/models" | wc -l) model files, $(ls "$GAME/img" | wc -l) pictures, $(ls "$GAME/music" | wc -l) songs"
rm -rf "$WORK"
