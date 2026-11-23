#!/bin/sh
# The cxbottle.conf rewrite, which is the only part of nvk-bottle that can be
# tested without a real bottle and a real runtime. Everything setup does to a
# prefix belongs to nvk-runtime; what belongs to this project is deciding what
# the file should say afterwards.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=bottle

NB="$ROOT/bin/nvk-bottle"
FIX="$ROOT/tests/fixtures/cxbottle-duplicates.conf"
out=$("$NB" clean-conf "$FIX")

printf '%s\n' "$TEST_NAME"

assert_not_contains "the managed block is removed" "$out" "managed by nvk-bottle"
assert_not_contains "the old sentinel is recognised too" "$out" "nvk-bottle.sh"
assert_not_contains "stray WINEDLLOVERRIDES copies are removed" "$out" "WINEDLLOVERRIDES"
assert_not_contains "stray DXVK_HUD copies are removed" "$out" "DXVK_HUD"
assert_not_contains "stray WINEMSYNC copies are removed" "$out" "WINEMSYNC"
assert_not_contains "CX_GRAPHICS_BACKEND is removed" "$out" "CX_GRAPHICS_BACKEND"

assert_contains "keys the block does not own are kept" "$out" "CX_BOTTLE_CREATOR_APPID"
assert_contains "commented lines are kept" "$out" ';;"PROMPT"'
assert_contains "other sections are kept" "$out" "[ManagedUpdatePolicy]"
assert_contains "the section header survives" "$out" "[EnvironmentVariables]"

# Running it twice must not differ from running it once: setup is re-runnable,
# and that is the reason the sentinel exists.
tmp=$(mktemp); printf '%s\n' "$out" > "$tmp"
assert_eq "cleaning is idempotent" "$out" "$("$NB" clean-conf "$tmp")"
rm -f "$tmp"

# Paths in this domain are full of spaces -- CrossOver's own default bottle
# directory has one. A --bottle-dir forwarded as a string holding a flag would
# split, and every tool that forwards it would stop finding the bottle.
SPACED="$ROOT/tests/fixtures/dir with spaces"
assert_eq "a bottle directory with a space is usable" \
  "$SPACED/spaced bottle" "$("$NB" --bottle-dir "$SPACED" path 'spaced bottle')"
assert_contains "and it is listed" \
  "$("$NB" --bottle-dir "$SPACED" list)" "spaced bottle"
assert_contains "nvk-doctor forwards it intact" \
  "$("$ROOT/bin/nvk-doctor" --color never --no-vulkan --no-checksums \
     --bottle-dir "$SPACED" --bottle 'spaced bottle' 2>&1)" "[ ok ] duplicate env keys"
assert_eq "nvk-winepath forwards it intact" 'C:\' \
  "$("$ROOT/bin/nvk-winepath" --bottle-dir "$SPACED" to-win 'spaced bottle' \
     "$SPACED/spaced bottle/drive_c")"
# Compare the value the launcher would actually hold, not the text of the
# line: the generated script quotes it, and the path this repository is
# checked out into may itself contain quotes.
gen_spaced=$("$ROOT/bin/nvk-mkapp" --bottle-dir "$SPACED" --bottle 'spaced bottle' \
     --runtime "$ROOT/tests/fixtures/fake-runtime" \
     --crossover "$ROOT/tests/fixtures/fake-crossover/CrossOver.app" \
     --app 'C:\x.exe' --name n --dry-run)
spaced_prefix=$(printf '%s\n' "$gen_spaced" | sed -n '/^PREFIX=/p' \
                | sh -c 'eval "$(cat)"; printf "%s" "$PREFIX"')
assert_eq "nvk-mkapp forwards it intact" "$SPACED/spaced bottle" "$spaced_prefix"

assert_rc "a missing file is an error" 1 "$NB" clean-conf /no/such/file.conf
assert_rc "an unknown subcommand is an error" 1 "$NB" not-a-command
assert_rc "path on an unknown bottle fails" 1 "$NB" path no-such-bottle-xyz

# dirs must not invent directories that do not exist. Bottle directories
# routinely contain spaces, so iterate on newlines, never on whitespace.
_bad=
oIFS=$IFS; IFS='
'
for d in $("$NB" dirs); do
  IFS=$oIFS
  [ -d "$d" ] || _bad="$d"
  IFS='
'
done
IFS=$oIFS
if [ -z "$_bad" ]; then _pass "dirs only lists directories that exist"
else _fail "dirs only lists directories that exist" "not a directory: $_bad"; fi

finish
