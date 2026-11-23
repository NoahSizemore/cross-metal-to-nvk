#!/bin/sh
# Contracts every tool shares. These exist because `--help` once exited 0 while
# printing nothing -- zsh sets $0 to the function name inside a function, so
# the usage text was read from a file named "usage". Exit status alone did not
# catch it, so these assertions look at the output.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib.sh"
TEST_NAME=cli

TOOLS='nvk-setup nvk-doctor nvk-bottle nvk-steam nvk-winepath nvk-profile nvk-mkapp'

printf '%s\n' "$TEST_NAME"

for t in $TOOLS; do
  bin="$ROOT/bin/$t"

  assert_eq "$t is executable" "yes" "$([ -x "$bin" ] && echo yes || echo no)"

  help=$("$bin" --help 2>&1 </dev/null)
  assert_rc "$t --help exits 0" 0 sh -c "'$bin' --help >/dev/null 2>&1 </dev/null"
  # A usage text that is merely non-empty is not enough; it has to be the real
  # one, which always names the tool and always documents at least one option.
  assert_contains "$t --help names the tool" "$help" "$t"
  assert_eq "$t --help is substantial" "yes" \
    "$([ "$(printf '%s' "$help" | wc -c | tr -d ' ')" -gt 400 ] && echo yes || echo no)"
  assert_contains "$t --help documents options" "$help" "--"

  assert_rc "$t rejects an unknown flag" 1 sh -c "'$bin' --definitely-not-a-flag >/dev/null 2>&1 </dev/null"

  # "Never require sudo" is design rule 2. Grepping for the word cannot test it
  # -- nvk-doctor legitimately prints sudo *advice* for the driver's failed-air
  # directory. Test the property instead: nothing may be setuid, and the whole
  # suite runs unprivileged.
  assert_eq "$t is not setuid or setgid" "" \
    "$(find "$bin" -perm -4000 -o -perm -2000 2>/dev/null)"
done

# The shebang each tool claims, since the zsh/sh split is a design rule.
for t in nvk-doctor nvk-bottle nvk-steam nvk-winepath nvk-profile nvk-mkapp; do
  assert_eq "$t is POSIX sh" "#!/bin/sh" "$(head -1 "$ROOT/bin/$t")"
done
assert_eq "nvk-setup is the only zsh script" "#!/bin/zsh" "$(head -1 "$ROOT/bin/nvk-setup")"

# Design rule 2: the tools that change something refuse to run as root. The
# read-only ones do not need to, and nvk-doctor deliberately only warns, since
# refusing to produce a diagnostic report helps nobody.
for t in nvk-setup nvk-bottle nvk-mkapp; do
  assert_contains "$t refuses to run as root" \
    "$(cat "$ROOT/bin/$t")" "do not run this as root"
done
assert_contains "nvk-doctor warns about root rather than refusing" \
  "$(cat "$ROOT/bin/nvk-doctor")" "Do not run this under sudo"

finish
