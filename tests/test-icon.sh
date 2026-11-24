#!/bin/sh
# nvk-icon's discovery and conversion. Discovery is tested against a fixture
# tree built here rather than against this machine's CrossOver, so the layout
# assumptions are checked on a machine that has neither CrossOver nor Steam.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=icon

NI="$ROOT/bin/nvk-icon"
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT INT TERM

printf '%s\n' "$TEST_NAME"

# A CrossOver layout: Programs sits beside Bottles, with the bottle's name as a
# subfolder, and the icon is always called CrossOverHelper.icns whatever the
# program is -- which is why the .app's name is what has to match.
mkdir -p "$T/Bottles/Steam" \
         "$T/Programs/Steam/Deadlock.app/Contents/Resources" \
         "$T/Programs/Steam/Other Game.app/Contents/Resources"
: > "$T/Programs/Steam/Deadlock.app/Contents/Resources/CrossOverHelper.icns"
: > "$T/Programs/Steam/Other Game.app/Contents/Resources/CrossOverHelper.icns"

out=$("$NI" find --bottle Steam --bottle-dir "$T/Bottles" --name Deadlock 2>/dev/null)
assert_eq "finds CrossOver's icns by the .app name" \
  "$T/Programs/Steam/Deadlock.app/Contents/Resources/CrossOverHelper.icns" "$out"

out=$("$NI" find --bottle Steam --bottle-dir "$T/Bottles" --name deadlock 2>/dev/null)
assert_eq "matching ignores case" \
  "$T/Programs/Steam/Deadlock.app/Contents/Resources/CrossOverHelper.icns" "$out"

# A name with a space must not be split into two candidates.
out=$("$NI" find --bottle Steam --bottle-dir "$T/Bottles" --name 'Other Game' 2>/dev/null)
assert_eq "a space in the name is handled" \
  "$T/Programs/Steam/Other Game.app/Contents/Resources/CrossOverHelper.icns" "$out"

assert_rc "an unknown game finds nothing" 2 \
  "$NI" find --bottle Steam --bottle-dir "$T/Bottles" --name NoSuchGame

# Steam's library cache: newer Steam buries artwork in hash-named directories,
# so the search must not assume a flat layout. logo.png outranks a capsule.
mkdir -p "$T/steam/appcache/librarycache/730/deadbeef"
: > "$T/steam/appcache/librarycache/730/deadbeef/logo.png"
: > "$T/steam/appcache/librarycache/730/library_capsule.jpg"

out=$("$NI" find --bottle Steam --bottle-dir "$T/Bottles" --name NoSuchGame \
        --appid 730 --steam-root "$T/steam" 2>/dev/null)
assert_eq "falls back to Steam artwork in a hash directory" \
  "$T/steam/appcache/librarycache/730/deadbeef/logo.png" "$out"

out=$("$NI" sources --bottle Steam --bottle-dir "$T/Bottles" --name Deadlock \
        --appid 730 --steam-root "$T/steam" 2>/dev/null | head -1 | cut -f1)
assert_eq "CrossOver outranks Steam artwork" "crossover" "$out"

n=$("$NI" sources --bottle Steam --bottle-dir "$T/Bottles" --name NoSuchGame \
      --appid 730 --steam-root "$T/steam" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "both Steam candidates are listed" "2" "$n"

# An appid with no steam root, and a steam root with no appid, must both be
# inert rather than erroring -- nvk-mkapp passes them unconditionally.
assert_rc "an empty appid and root are not an error" 2 \
  "$NI" find --bottle Steam --bottle-dir "$T/Bottles" --name NoSuchGame \
  --appid '' --steam-root ''

assert_rc "a missing source file is an error" 1 "$NI" make "$T/nope.png" "$T/out.icns"
assert_rc "the destination must be .icns" 1 "$NI" make "$T/nope.png" "$T/out.png"
assert_rc "an unknown command is an error" 1 "$NI" not-a-command

# Conversion needs macOS image tools; skip where they are absent rather than
# failing a suite that is meant to run anywhere.
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  printf 'x' > "$T/fake.icns"
  "$NI" make "$T/fake.icns" "$T/copy.icns" >/dev/null 2>&1
  assert_eq "an .icns source is copied, not re-encoded" "x" "$(cat "$T/copy.icns")"
else
  _pass "conversion tools absent; skipped"
fi

finish
