#!/bin/sh
# Steam discovery, against fixtures rather than this machine. The fixture
# bottle deliberately has two library roots, a game whose folder is not its
# name, a game on a second volume, Steam's own non-game plumbing, and a game
# whose name contains quotes, backslashes and shell metacharacters.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=steam

ST="$ROOT/bin/nvk-steam"
B="$ROOT/tests/fixtures/bottle"
APPS="$B/drive_c/Program Files (x86)/Steam/steamapps"
LIB2="$B/volume_d/SteamLibrary/steamapps"
COMMON1="$APPS/common"
COMMON2="$LIB2/common"

printf '%s\n' "$TEST_NAME"

# --- KeyValues parsing ---------------------------------------------------
kvout=$("$ST" kv "$APPS/appmanifest_730.acf")
assert_contains "kv reports depth, key and value" "$kvout" "1	appid	730"
assert_contains "kv descends into nested sections" "$kvout" "3	manifest	"

assert_eq "parse-acf reads appid, name and installdir" \
  "730	Counter-Strike 2	Counter-Strike Global Offensive" \
  "$("$ST" parse-acf "$APPS/appmanifest_730.acf")"

# A nested "name" inside InstalledDepots must not win over the real one.
assert_not_contains "a nested name is not mistaken for the game's" \
  "$("$ST" parse-acf "$APPS/appmanifest_730.acf")" "must not be mistaken"

# Valve escapes \" and \\ inside values; the parser has to undo both.
expected_name=$(cat "$ROOT/tests/fixtures/expected-999001-name.txt")
assert_eq "parse-acf unescapes quotes and backslashes" \
  "$expected_name" "$("$ST" parse-acf "$LIB2/appmanifest_999001.acf" | cut -f2)"

assert_eq "parse-libraryfolders finds every root" \
  'C:\Program Files (x86)\Steam D:\SteamLibrary' \
  "$("$ST" parse-libraryfolders "$APPS/libraryfolders.vdf" | tr '\n' ' ' | sed 's/ $//')"

assert_rc "a file that is not KeyValues is an error" 1 "$ST" parse-acf "$ROOT/README.md"

# Windows line endings: the brace that opens a section arrives as "{\r", which
# used to stop depth tracking and put every key at the wrong level.
assert_eq "a manifest with CRLF line endings parses" \
  "555000	CRLF Game	CRLF Dir" \
  "$("$ST" parse-acf "$ROOT/tests/fixtures/appmanifest-crlf.acf")"
assert_not_contains "CRLF values carry no carriage return" \
  "$("$ST" parse-acf "$ROOT/tests/fixtures/appmanifest-crlf.acf" | od -c | tr -d ' ')" '\\r'
assert_not_contains "a nested name is still ignored under CRLF" \
  "$("$ST" parse-acf "$ROOT/tests/fixtures/appmanifest-crlf.acf")" "nested"

# --- discovery -----------------------------------------------------------
assert_eq "root finds the Steam directory" \
  "$(CDPATH= cd -- "$B/drive_c/Program Files (x86)/Steam" && pwd -P)" \
  "$("$ST" root "$B")"

libs=$("$ST" libraries "$B")
assert_line_count "libraries returns both roots, not one" "$libs" 2
assert_contains "libraries includes the second volume" "$libs" "volume_d/SteamLibrary"
assert_line_count "libraries does not list the primary root twice" \
  "$(printf '%s\n' "$libs" | sort -u)" 2

games=$("$ST" games "$B")
assert_line_count "games lists three games" "$games" 3
assert_contains "games resolves a store name that differs from its folder" \
  "$games" "730	Counter-Strike 2	Counter-Strike Global Offensive"
assert_contains "games finds a game on the second volume" "$games" "1422450	Deadlock"
assert_not_contains "games hides Steam's own redistributables" "$games" "228980"
assert_contains "games --all shows them" "$("$ST" games "$B" --all)" "228980"

# --- executable ranking --------------------------------------------------
cs=$("$ST" exes "$COMMON1/Counter-Strike Global Offensive")
assert_contains "the game binary ranks first" "$(printf '%s\n' "$cs" | head -1)" "cs2.exe"
assert_not_contains "crash handlers are dropped" "$cs" "crashhandler"
assert_contains "a launcher is kept but demoted" "$cs" "csgo_launcher.exe"
assert_eq "the launcher is not first despite being the largest file" \
  "0" "$(printf '%s\n' "$cs" | head -1 | grep -c launcher || true)"

# A trailing slash must not shift the relative path used for layout matching.
assert_eq "a trailing slash on the game directory changes nothing" \
  "$("$ST" exes "$COMMON2/Deadlock")" "$("$ST" exes "$COMMON2/Deadlock/")"

ue=$("$ST" exes "$COMMON2/Toms Game")
assert_contains "an Unreal shipping binary ranks first" \
  "$(printf '%s\n' "$ue" | head -1)" "TomsGame-Win64-Shipping.exe"
assert_not_contains "engine crash reporters are dropped" "$ue" "CrashReportClient"
assert_not_contains "the editor is dropped" "$ue" "UnrealEditor"
assert_not_contains "bundled redistributables are dropped" "$ue" "vcredist"
assert_not_contains "anticheat binaries are not launch candidates" "$ue" "EasyAntiCheat"
assert_contains "--all keeps what ranking dropped" \
  "$("$ST" exes "$COMMON2/Toms Game" --all)" "vcredist"

# --- anticheat -----------------------------------------------------------
ac=$("$ST" anticheat "$COMMON2/Toms Game")
assert_contains "anticheat is detected" "$ac" "EasyAntiCheat"
assert_eq "a game without anticheat reports none" "" "$("$ST" anticheat "$COMMON2/Deadlock")"

finish
