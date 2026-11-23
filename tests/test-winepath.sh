#!/bin/sh
# Unix <-> Windows path mapping, against a fixture bottle whose drives are
# relative symlinks, so the expected answers are the same on every machine.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=winepath

WP="$ROOT/bin/nvk-winepath"
B="$ROOT/tests/fixtures/bottle"
C=$(CDPATH= cd -- "$B/drive_c" && pwd -P)
D=$(CDPATH= cd -- "$B/volume_d" && pwd -P)

printf '%s\n' "$TEST_NAME"

assert_eq "drives lists C, D and E" \
  "C D E" "$("$WP" drives "$B" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"

assert_not_contains "a device node is not a drive" \
  "$("$WP" drives "$B")" "rdisk"

assert_eq "to-win maps drive_c to C:" \
  'C:\Program Files (x86)\Steam\steam.exe' \
  "$("$WP" to-win "$B" "$C/Program Files (x86)/Steam/steam.exe")"

# The whole point: a library on a second volume is not under C:.
assert_eq "to-win maps the second volume to its own letter" \
  'D:\SteamLibrary\steamapps\common\Deadlock\game\bin\win64\deadlock.exe' \
  "$("$WP" to-win "$B" "$D/SteamLibrary/steamapps/common/Deadlock/game/bin/win64/deadlock.exe")"

assert_eq "to-win handles a drive root" "C:\\" "$("$WP" to-win "$B" "$C")"

assert_eq "to-win keeps spaces and parentheses intact" \
  'D:\SteamLibrary\steamapps\common\Toms Game\Binaries\Win64\TomsGame-Win64-Shipping.exe' \
  "$("$WP" to-win "$B" "$D/SteamLibrary/steamapps/common/Toms Game/Binaries/Win64/TomsGame-Win64-Shipping.exe")"

assert_eq "to-win maps a path that does not exist yet" \
  'C:\does not\exist.exe' "$("$WP" to-win "$B" "$C/does not/exist.exe")"

assert_eq "from-win is the inverse" \
  "$C/Program Files (x86)/Steam/steam.exe" \
  "$("$WP" from-win "$B" 'C:\Program Files (x86)\Steam\steam.exe')"

assert_eq "from-win accepts a lowercase drive letter" \
  "$D/SteamLibrary" "$("$WP" from-win "$B" 'd:\SteamLibrary')"

assert_eq "from-win handles a bare drive" "$C" "$("$WP" from-win "$B" 'C:')"

rt=$("$WP" to-win "$B" "$D/SteamLibrary/steamapps/common/Toms Game")
assert_eq "round trip survives a space" \
  "$D/SteamLibrary/steamapps/common/Toms Game" "$("$WP" from-win "$B" "$rt")"

assert_rc "a missing drive letter is an error" 1 "$WP" from-win "$B" 'Q:\nope'
assert_rc "a relative Windows path is an error" 1 "$WP" from-win "$B" 'not-a-path'
assert_rc "a UNC path is refused" 1 "$WP" from-win "$B" '\\server\share'
assert_rc "an unknown bottle is an error" 1 "$WP" drives no-such-bottle-xyz

finish
