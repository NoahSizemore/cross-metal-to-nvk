#!/bin/sh
# Launcher generation. A wizard that accepts typed paths and game names and
# writes them into a generated shell script is an injection path into your own
# launcher, so these tests are mostly about hostile input surviving intact and
# staying inert.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=mkapp

MK="$ROOT/bin/nvk-mkapp"
NP="$ROOT/bin/nvk-profile"
FIX="$ROOT/tests/fixtures"
CXA="$FIX/fake-crossover/CrossOver.app"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Wrappers rather than strings of flags: the repository may live in a path with
# spaces, and an unquoted expansion would split it. $FIX provides stand-ins so
# this runs on a machine with no CrossOver and no NVK runtime.
mk()  { "$MK" --bottle-dir "$FIX" --bottle bottle --runtime "$FIX/fake-runtime" \
              --crossover "$CXA" "$@" </dev/null; }
mkp() { "$MK" --bottle-dir "$FIX" --runtime "$FIX/fake-runtime" \
              --crossover "$CXA" "$@" </dev/null; }

HOSTILE='Tom'"'"'s "Game" & <stuff> $(touch '"$TMP"'/PWNED) `touch '"$TMP"'/PWNED2` \back'

printf '%s\n' "$TEST_NAME"

gen=$(mk --app 'D:\Games\Tom'"'"'s "Game"\game.exe' --name "$HOSTILE" \
         --arg '-dx11' --arg 'two words' --arg "it's" --dry-run 2>/dev/null)

assert_rc "a hostile name produces valid shell" 0 sh -c 'printf "%s\n" "$1" | sh -n' _ "$gen"

# Run only the prelude, which is where every interpolated value lands, and
# read the values back out of the running shell.
probe="$TMP/probe.sh"
printf '%s\n' "$gen" | sed -n '1,/^eval "set --/p' > "$probe"
cat >> "$probe" <<'P'
printf 'APP=[%s]\n' "$APP"
printf 'TITLE=[%s]\n' "$TITLE"
printf 'PREFIX=[%s]\n' "$PREFIX"
printf 'argc=[%d]\n' "$#"
printf 'arg2=[%s]\n' "$2"
printf 'arg3=[%s]\n' "$3"
P
out=$(HOME="$TMP" sh "$probe")

assert_contains "the exe path round-trips with a quote in it" "$out" \
  'APP=[D:\Games\Tom'"'"'s "Game"\game.exe]'
assert_contains "the title round-trips verbatim" "$out" "TITLE=[$HOSTILE]"
assert_eq "nothing in the name was executed" "no" \
  "$([ -e "$TMP/PWNED" ] || [ -e "$TMP/PWNED2" ] && echo yes || echo no)"

assert_contains "arguments are not re-split on spaces" "$out" "argc=[3]"
assert_contains "an argument with spaces stays one argument" "$out" "arg2=[two words]"
assert_contains "an argument with a quote survives" "$out" "arg3=[it's]"
assert_contains "paths are pinned absolute" "$out" "PREFIX=[/"

assert_contains "a relative --runtime is made absolute" \
  "$("$MK" --bottle-dir "$FIX" --bottle bottle --runtime tests/fixtures/fake-runtime \
      --crossover "$CXA" --app 'C:\x.exe' --name n --dry-run 2>/dev/null \
      || mk --app 'C:\x.exe' --name n --dry-run)" "RUNTIME='/"

# --- the bundle ----------------------------------------------------------
# A filename cannot contain the temp path, so use a name that is hostile in
# every other way for the parts that touch disk.
BUNDLE_NAME='Tom'"'"'s "Game" & <stuff> $(id) `id` \back'
mk --app 'C:\x.exe' --name "$BUNDLE_NAME" --outdir "$TMP/apps" >/dev/null 2>&1
app=$(find "$TMP/apps" -maxdepth 1 -name '*.app' | head -1)
assert_eq "a bundle is created" "yes" "$([ -n "$app" ] && echo yes || echo no)"
assert_rc "its Info.plist is valid" 0 plutil -lint "$app/Contents/Info.plist"
assert_rc "its launcher is valid shell" 0 sh -n "$app/Contents/MacOS/launch"
assert_eq "its launcher is executable" "yes" \
  "$([ -x "$app/Contents/MacOS/launch" ] && echo yes || echo no)"
assert_eq "the name survives XML escaping" "$BUNDLE_NAME" \
  "$(plutil -extract CFBundleName raw "$app/Contents/Info.plist" 2>/dev/null)"

# A slash in a game name must not become a directory separator.
mk --app 'C:\x.exe' --name 'Trackmania / Nations' --outdir "$TMP/slash" >/dev/null 2>&1
assert_eq "a slash in the name does not create nested directories" "1" \
  "$(find "$TMP/slash" -maxdepth 1 -name '*.app' | grep -c . || true)"
assert_eq "the full name is still what the bundle displays" "Trackmania / Nations" \
  "$(plutil -extract CFBundleName raw \
     "$(find "$TMP/slash" -maxdepth 1 -name '*.app' | head -1)/Contents/Info.plist" 2>/dev/null)"

# --- profiles ------------------------------------------------------------
P1="$TMP/prof.conf"
"$NP" write "$P1" schema=1 appid=42 'name=Fixture Game' bottle=bottle \
  'exe_win=C:\from\profile.exe' 'args=-fromprofile' 'dxvk_config=dxvk.test = True' >/dev/null

gp=$(mkp --profile "$P1" --dry-run)
assert_contains "a profile supplies the exe" "$gp" "APP='C:\\from\\profile.exe'"
assert_contains "a profile supplies the arguments" "$gp" "'-fromprofile'"
assert_contains "a profile supplies DXVK_CONFIG" "$gp" "dxvk.test = True"
assert_contains "the app name defaults to the game plus (NVK)" "$gp" "TITLE='Fixture Game (NVK)'"

go=$(mkp --profile "$P1" --args '-override' --name 'Overridden' --dry-run)
assert_contains "a flag overrides the profile's arguments" "$go" "'-override'"
assert_not_contains "the profile's arguments are gone" "$go" "fromprofile"
assert_contains "a flag overrides the profile's name" "$go" "TITLE='Overridden'"

# --save-profile must record what was actually built.
mk --app 'C:\saved.exe' --name 'Saved' --args '-saved' \
   --outdir "$TMP/apps" --save-profile "$TMP/saved.conf" >/dev/null 2>&1
assert_eq "--save-profile records the exe" 'C:\saved.exe' \
  "$("$NP" read "$TMP/saved.conf" exe_win)"
assert_eq "--save-profile records the arguments" '-saved' \
  "$("$NP" read "$TMP/saved.conf" args)"
assert_rc "--save-profile writes a valid profile" 0 "$NP" validate "$TMP/saved.conf"

# Arguments given one at a time have to survive into the profile, or
# --regenerate-all silently rebuilds the launcher without them.
mk --app 'C:\argtest.exe' --name 'ArgTest' --arg '-alpha' --arg '-beta' \
   --outdir "$TMP/apps" --save-profile "$TMP/args.conf" >/dev/null 2>&1
assert_eq "--arg reaches the profile, not just the launcher" "-alpha -beta" \
  "$("$NP" read "$TMP/args.conf" args)"
assert_contains "and survives a rebuild from that profile" \
  "$(mkp --profile "$TMP/args.conf" --dry-run)" "'-alpha' '-beta'"
assert_contains "an argument a profile cannot hold is warned about, not dropped" \
  "$(mk --app 'C:\x.exe' --name 'W' --arg 'two words' --dry-run 2>&1 >/dev/null)" \
  "cannot record it faithfully"

# --- regenerate-all ------------------------------------------------------
mkdir -p "$TMP/profiles"
cp "$P1" "$TMP/profiles/a.conf"
"$NP" write "$TMP/profiles/b.conf" schema=1 'name=Second' bottle=bottle \
  'exe_win=C:\second.exe' >/dev/null
ra=$(mkp --regenerate-all --profile-dir "$TMP/profiles" --outdir "$TMP/apps2" 2>&1)
assert_contains "regenerate-all reports the count" "$ra" "2 profile(s), 0 failed"
assert_eq "regenerate-all builds every profile" "2" \
  "$(find "$TMP/apps2" -maxdepth 1 -name '*.app' | grep -c . || true)"

# --- refusals ------------------------------------------------------------
assert_rc "an unknown bottle is refused" 1 "$MK" --bottle-dir "$FIX" --bottle nope \
  --runtime "$FIX/fake-runtime" --crossover "$CXA" --app 'C:\x.exe' --dry-run
assert_rc "a missing runtime is refused" 1 "$MK" --bottle-dir "$FIX" --bottle bottle \
  --runtime "$TMP/no-runtime" --crossover "$CXA" --app 'C:\x.exe' --dry-run
assert_rc "a missing --app is refused" 1 "$MK" --bottle-dir "$FIX" --bottle bottle \
  --runtime "$FIX/fake-runtime" --crossover "$CXA" --dry-run
assert_rc "an unknown flag is refused" 1 "$MK" --nonsense

finish
