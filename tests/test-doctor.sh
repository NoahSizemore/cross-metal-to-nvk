#!/bin/sh
# The preflight gate. The host and GPU checks describe the machine the tests
# happen to run on, so they are not asserted here; what is asserted is that the
# bottle analysis is correct and that the exit status follows the worst finding.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=doctor

DR="$ROOT/bin/nvk-doctor"
FIX="$ROOT/tests/fixtures"

# A wrapper, not a string of flags: the repository may be cloned into a path
# with spaces in it, and an unquoted expansion would split it.
dr() { "$DR" --color never --no-vulkan --no-checksums --bottle-dir "$FIX" "$@" </dev/null; }

printf '%s\n' "$TEST_NAME"

assert_rc "--version works" 0 "$DR" --version
assert_rc "--help works" 0 "$DR" --help
assert_rc "an unknown flag is refused" 1 "$DR" --nonsense
assert_rc "a bad --color value is refused" 1 "$DR" --color mauve

out=$(dr --bottle bottle 2>&1)
assert_contains "it names the prefix it examined" "$out" "fixtures/bottle"
assert_contains "a missing DXVK pair is fatal" "$out" "[FAIL] d3d11.dll"
assert_contains "an unconfigured bottle is fatal" "$out" "managed env block"
assert_contains "CX_GRAPHICS_BACKEND is flagged" "$out" "CX_GRAPHICS_BACKEND"
assert_contains "optional vkd3d is not fatal" "$out" "[info] d3d12.dll"
assert_contains "it tells you what to run next" "$out" "nvk-bottle setup bottle"
assert_contains "a failure means do not continue" "$out" "Not ready"

dup=$(dr --bottle bottle-configured 2>&1)
assert_contains "a configured bottle is recognised" "$dup" "[ ok ] managed env block"
assert_contains "duplicated keys are reported" "$dup" "duplicate env keys"
assert_contains "every duplicate is named" "$dup" "WINEDLLOVERRIDES"
assert_contains "including the HUD key" "$dup" "DXVK_HUD"
assert_contains "the registry overrides are read" "$dup" "d3d11, dxgi = native"

# vkd3d only matters when the bottle actually routes d3d12 to a native DLL.
# A bottle that does not is using CrossOver's builtin, which NVK never sees,
# so comparing it against the runtime would report on something out of the chain.
assert_contains "an unused vkd3d pair is noted, not judged" "$dup" \
  "present but not in use"
assert_not_contains "and it does not make the bottle fail" "$dup" \
  "[FAIL] d3d12.dll"

d12=$(dr --bottle bottle-d3d12 2>&1)
assert_contains "a bottle that routes d3d12 with no DLL is a failure" "$d12" \
  "[FAIL] d3d12.dll"
assert_contains "and it says which command fixes it" "$d12" \
  "nvk-bottle setup bottle-d3d12 --d3d12"

assert_contains "an unknown bottle is reported, not ignored" \
  "$(dr --bottle no-such-bottle 2>&1)" "not found"

# Report-only runs must never change anything. nvk-doctor claims to be
# read-only, so prove it against the fixture tree.
before=$(find "$FIX" -print0 2>/dev/null | sort -z | xargs -0 shasum 2>/dev/null | shasum)
dr --all-bottles >/dev/null 2>&1
after=$(find "$FIX" -print0 2>/dev/null | sort -z | xargs -0 shasum 2>/dev/null | shasum)
assert_eq "nvk-doctor changes nothing" "$before" "$after"

finish
