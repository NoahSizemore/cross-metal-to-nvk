#!/bin/sh
# The wizard, driven entirely by flags. Every question it asks must also be
# answerable on the command line, so that a working setup reproduces as one
# line and a bug report can be a command rather than a story. These tests are
# that promise, checked.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=setup

SU="$ROOT/bin/nvk-setup"
NP="$ROOT/bin/nvk-profile"
FIX="$ROOT/tests/fixtures"
CXA="$FIX/fake-crossover/CrossOver.app"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A wrapper, not a string of flags: the repository may be cloned into a path
# with spaces. stdin is closed so a missed prompt fails instead of hanging.
su() {
  "$SU" --bottle-dir "$FIX" --bottle bottle \
        --runtime "$FIX/fake-runtime" --crossover "$CXA" \
        --skip-doctor --skip-bottle-setup "$@" </dev/null
}

printf '%s\n' "$TEST_NAME"

out=$(su --game Deadlock --args '-dx11' --yes --dry-run 2>&1)
assert_rc "a fully flagged run needs no input" 0 su --game Deadlock --args '-dx11' --yes --dry-run
assert_contains "it resolves the game" "$out" "Deadlock (1422450)"
assert_contains "it picks the ranked executable" "$out" "deadlock.exe"
assert_contains "it maps to the right drive, not C:" "$out" 'D:\SteamLibrary'
assert_contains "it reports the arguments" "$out" "-dx11"
assert_contains "it defaults to the two-app split" "$out" "Steam (NVK).app"
assert_contains "a dry run writes nothing" "$out" "nothing was written"

# A store name nobody types exactly must still resolve.
assert_contains "a partial name matches" \
  "$(su --game counter-strike --yes --dry-run 2>&1)" "Counter-Strike 2 (730)"
assert_contains "an appid matches" \
  "$(su --game 730 --yes --dry-run 2>&1)" "Counter-Strike 2 (730)"

miss=$(su --game "No Such Game" --yes --dry-run 2>&1)
assert_contains "an unknown game says so" "$miss" "no installed game matches"
assert_contains "and lists what is installed" "$miss" "Counter-Strike 2 (730)"
assert_rc "and exits non-zero" 1 su --game "No Such Game" --yes --dry-run

# --- anticheat -----------------------------------------------------------
ac=$(su --game "Tom's" --yes --dry-run 2>&1)
assert_contains "anticheat is reported plainly" "$ac" "ships anticheat: EasyAntiCheat"
assert_contains "and the limitation is explained" "$ac" "does not work"
assert_rc "and it stops by default" 1 su --game "Tom's" --yes --dry-run
assert_contains "--allow-anticheat continues" \
  "$(su --game "Tom's" --allow-anticheat --yes --dry-run 2>&1)" "Summary"

# --- what it writes ------------------------------------------------------
su --game Deadlock --args '-dx11' --outdir "$TMP/apps" \
   --profile-dir "$TMP/prof" --yes >/dev/null 2>&1
prof=$(find "$TMP/prof" -name '*.conf' | head -1)
assert_eq "it writes a profile" "yes" "$([ -n "$prof" ] && echo yes || echo no)"
assert_rc "the profile is valid" 0 "$NP" validate "$prof"
assert_eq "the profile records the appid" "1422450" "$("$NP" read "$prof" appid)"
assert_eq "the profile records the mapped exe" \
  'D:\SteamLibrary\steamapps\common\Deadlock\game\bin\win64\deadlock.exe' \
  "$("$NP" read "$prof" exe_win)"
assert_eq "it generates both launchers" "2" \
  "$(find "$TMP/apps" -maxdepth 1 -name '*.app' | grep -c . || true)"
for l in "$TMP"/apps/*.app/Contents/MacOS/launch; do
  [ -f "$l" ] || continue
  assert_rc "a generated launcher is valid shell" 0 sh -n "$l"
done

# --- the flags that change the shape of the result -----------------------
su --game Deadlock --no-steam-app --outdir "$TMP/apps2" \
   --profile-dir "$TMP/prof2" --yes >/dev/null 2>&1
assert_eq "--no-steam-app generates one launcher" "1" \
  "$(find "$TMP/apps2" -maxdepth 1 -name '*.app' | grep -c . || true)"

su --game Deadlock --needs-steam --outdir "$TMP/apps3" \
   --profile-dir "$TMP/prof3" --yes >/dev/null 2>&1
assert_eq "--needs-steam is recorded in the profile" "yes" \
  "$("$NP" read "$(find "$TMP/prof3" -name '*.conf' | head -1)" needs_steam)"

assert_contains "--exe bypasses the picker" \
  "$(su --game Deadlock --exe 'C:\chosen\by\hand.exe' --yes --dry-run 2>&1)" \
  'C:\chosen\by\hand.exe'

# --- refusals ------------------------------------------------------------
assert_rc "an unknown bottle is refused" 1 "$SU" --bottle-dir "$FIX" --bottle nope \
  --skip-doctor --yes --dry-run
assert_rc "an unknown flag is refused" 1 "$SU" --nonsense
# Exit status alone is not enough: a --help that prints nothing still exits 0,
# which is exactly how this shipped broken once.
help=$("$SU" --help 2>&1)
assert_rc "--help exits cleanly" 0 "$SU" --help
assert_contains "--help describes the tool" "$help" "nvk-setup"
for f in --bottle --game --exe --args --needs-steam --no-steam-app --outdir \
         --profile-dir --bottle-dir --runtime --crossover --allow-anticheat \
         --skip-doctor --skip-bottle-setup --force --yes --dry-run; do
  assert_contains "--help documents $f" "$help" "$f"
done

finish
