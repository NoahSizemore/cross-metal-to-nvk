#!/bin/sh
# Profiles are read line by line and never sourced, because they are meant to
# be shared. These tests pin that contract down.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=profile

NP="$ROOT/bin/nvk-profile"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
F="$TMP/p.conf"

printf '%s\n' "$TEST_NAME"

"$NP" write "$F" schema=1 appid=730 'name=Counter-Strike 2' bottle=Steam \
  'exe_win=C:\Program Files (x86)\Steam\cs2.exe' >/dev/null

assert_eq "a value survives spaces and parentheses" \
  'C:\Program Files (x86)\Steam\cs2.exe' "$("$NP" read "$F" exe_win)"
assert_eq "a value survives being a sentence" "Counter-Strike 2" "$("$NP" read "$F" name)"

# Values that would execute if the file were ever sourced.
"$NP" write "$F" 'notes=$(touch '"$TMP"'/PWNED) `touch '"$TMP"'/PWNED2` ; rm -rf /' >/dev/null
out=$("$NP" read "$F" notes)
assert_contains "shell metacharacters are stored verbatim" "$out" 'rm -rf /'
assert_eq "reading a profile executes nothing" "no" \
  "$([ -e "$TMP/PWNED" ] || [ -e "$TMP/PWNED2" ] && echo yes || echo no)"

# An = in the value must not be mistaken for the separator.
"$NP" write "$F" 'dxvk_config=dxvk.enableDescriptorBuffer = False' >/dev/null
assert_eq "an equals sign in a value is kept" \
  "dxvk.enableDescriptorBuffer = False" "$("$NP" read "$F" dxvk_config)"

"$NP" write "$F" 'name=Renamed' >/dev/null
assert_eq "writing a key replaces it rather than duplicating" "Renamed" "$("$NP" read "$F" name)"
assert_eq "a replaced key appears exactly once" "1" \
  "$("$NP" read "$F" | grep -c '^name=')"
assert_eq "other keys survive a write" "730" "$("$NP" read "$F" appid)"

assert_rc "a newline in a value is refused" 1 "$NP" write "$F" "notes=one
two"
assert_rc "an invalid key is refused" 1 "$NP" write "$F" "Bad-Key=x"
assert_rc "a bare word is refused" 1 "$NP" write "$F" "nokey"

assert_rc "a complete profile validates" 0 "$NP" validate "$F"

B="$TMP/bad.conf"
"$NP" write "$B" schema=9 'exe_win=relative\path.exe' needs_steam=perhaps appid=xyz >/dev/null
assert_rc "a bad profile fails validation" 2 "$NP" validate "$B"
err=$("$NP" validate "$B" 2>&1 >/dev/null)
assert_contains "it says the schema is wrong" "$err" "schema"
assert_contains "it says bottle is missing" "$err" "bottle is required"
assert_contains "it says the exe path is not absolute" "$err" "not an absolute Windows path"
assert_contains "it says needs_steam is wrong" "$err" "needs_steam must be"
assert_contains "it says appid is not numeric" "$err" "appid is not numeric"

U="$TMP/unknown.conf"
"$NP" write "$U" schema=1 bottle=Steam 'exe_win=C:\x.exe' >/dev/null
printf 'from_the_future=yes\n' >> "$U"
assert_rc "an unknown key is a note, not a failure" 0 "$NP" validate "$U"
assert_contains "the unknown key is mentioned" \
  "$("$NP" validate "$U" 2>&1 >/dev/null)" "from_the_future"
assert_eq "an unknown key is not dropped by a later write" "yes" \
  "$("$NP" write "$U" bottle=Other >/dev/null; "$NP" read "$U" from_the_future)"

assert_eq "a filename is slugged with its appid" "counter-strike-2-730.conf" \
  "$("$NP" name "Counter-Strike 2" 730)"
assert_eq "a filename without an appid drops the suffix" "deadlock.conf" \
  "$("$NP" name "Deadlock")"
assert_eq "a hostile name still yields a sane filename" "tom-s-game-2024.conf" \
  "$("$NP" name 'Tom'"'"'s "Game" (2024)')"

assert_rc "reading a missing profile is an error" 1 "$NP" read "$TMP/nope.conf"

# The profiles shipped with the repository must themselves be valid.
for f in "$ROOT"/profiles/*.conf; do
  [ -f "$f" ] || continue
  assert_rc "shipped profile validates: $(basename "$f")" 0 "$NP" validate "$f"
done

finish
