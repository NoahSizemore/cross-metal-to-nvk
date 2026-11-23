# Shared assertions for the nvk test scripts. POSIX sh; sourced, not run.
#
# Tests must work on a machine that has no NVIDIA GPU, no CrossOver and no
# Steam. Anything that needs this machine's hardware belongs in nvk-doctor,
# not here.

TESTS_RUN=0
TESTS_FAILED=0

_pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  ok   %s\n' "$1"; }
_fail() {
  TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL %s\n' "$1"
  shift
  for l in "$@"; do printf '         %s\n' "$l"; done
}

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then _pass "$1"
  else _fail "$1" "expected: $2" "actual:   $3"; fi
}

assert_contains() { # name haystack needle
  case $2 in
    *"$3"*) _pass "$1" ;;
    *) _fail "$1" "expected to contain: $3" "actual: $2" ;;
  esac
}

assert_not_contains() { # name haystack needle
  case $2 in
    *"$3"*) _fail "$1" "expected NOT to contain: $3" "actual: $2" ;;
    *) _pass "$1" ;;
  esac
}

assert_rc() { # name expected-rc command...
  _name=$1; _want=$2; shift 2
  "$@" >/dev/null 2>&1; _got=$?
  if [ "$_got" -eq "$_want" ]; then _pass "$_name"
  else _fail "$_name" "expected exit $_want, got $_got" "command: $*"; fi
}

assert_line_count() { # name expected text
  _n=$(printf '%s\n' "$2" | grep -c . || true)
  if [ "$_n" -eq "$3" ] 2>/dev/null; then _pass "$1"
  else _fail "$1" "expected $3 non-empty lines, got $_n" "text: $2"; fi
}

finish() {
  printf '\n%s: %d run, %d failed\n' "${TEST_NAME:-tests}" "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ] || exit 1
  exit 0
}
