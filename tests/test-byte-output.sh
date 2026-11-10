#!/usr/bin/env bash
# Byte-level tests for tui-mode-recovery wrappers.
# Uses a fake TUI binary + a real pty (script) + grep on the raw bytes:
#   1. trigger case emits the exact two-screen cleanup sequence
#   2. exit code is preserved through the wrapper
#   3. piped stdout emits nothing
#   4. non-matching args emit nothing
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"

EXPECTED="$(printf '\033[?1049h\033[<u\033[<u\033[<u\033[=0u\033[?1049l\033[<u\033[<u\033[<u\033[=0u\033[>4m\033[?1004l\033[?2004l\033[?25h')"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho FAKE-RAN "$@"\nexit 7\n' > "$TMP/bin/hermes"
chmod +x "$TMP/bin/hermes"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

assert_has_seq() { # $1 label  $2 file
    if grep -qF -- "$EXPECTED" "$2"; then ok "$1"; else bad "$1 (cleanup sequence missing)"; fi
}
assert_no_esc() { # $1 label  $2 file
    if ! grep -q $'\033' "$2"; then ok "$1"; else bad "$1 (unexpected escape bytes)"; fi
}
assert_rc7() { # $1 label  $2 file
    if grep -aq 'rc=7' "$2"; then ok "$1"; else bad "$1 (exit code 7 not preserved)"; fi
}

# ---------- fish: functions/hermes.fish ----------
printf 'hermes --tui\necho "rc=$status"\n' > "$TMP/fish_trigger.fish"
printf 'hermes chat -q hi\necho "rc=$status"\n' > "$TMP/fish_other.fish"

cat > "$TMP/fishrun.sh" <<EOF
#!/usr/bin/env bash
export PATH="$TMP/bin:\$PATH"
exec fish "\$@"
EOF
chmod +x "$TMP/fishrun.sh"

script -qec "$TMP/fishrun.sh $TMP/fish_trigger.fish" /dev/null > "$TMP/fish_trigger.out"
script -qec "$TMP/fishrun.sh $TMP/fish_other.fish" /dev/null > "$TMP/fish_other.out"
"$TMP/fishrun.sh" "$TMP/fish_trigger.fish" > "$TMP/fish_piped.out" 2>&1

assert_has_seq "fish: --tui emits two-screen cleanup (pty)" "$TMP/fish_trigger.out"
assert_rc7 "fish: exit code preserved" "$TMP/fish_trigger.out"
assert_no_esc "fish: piped stdout stays clean" "$TMP/fish_piped.out"
assert_no_esc "fish: non-tui args emit nothing" "$TMP/fish_other.out"

# ---------- bash: lib/tui-recover.sh (tmr) ----------
cat > "$TMP/bashrun.sh" <<EOF
#!/usr/bin/env bash
export PATH="$TMP/bin:\$PATH"
source "$REPO/lib/tui-recover.sh"
tmr hermes --tui
echo "rc=\$?"
EOF
chmod +x "$TMP/bashrun.sh"

script -qec "$TMP/bashrun.sh" /dev/null > "$TMP/bash_trigger.out"
"$TMP/bashrun.sh" > "$TMP/bash_piped.out" 2>&1

assert_has_seq "bash tmr: emits two-screen cleanup (pty)" "$TMP/bash_trigger.out"
assert_rc7 "bash tmr: exit code preserved" "$TMP/bash_trigger.out"
assert_no_esc "bash tmr: piped stdout stays clean" "$TMP/bash_piped.out"

# ---------- zsh: same lib ----------
cat > "$TMP/zshrun.sh" <<EOF
#!/usr/bin/env zsh
export PATH="$TMP/bin:\$PATH"
source "$REPO/lib/tui-recover.sh"
tmr hermes --tui
echo "rc=\$?"
EOF
chmod +x "$TMP/zshrun.sh"
script -qec "$TMP/zshrun.sh" /dev/null > "$TMP/zsh_trigger.out"
assert_has_seq "zsh tmr: emits two-screen cleanup (pty)" "$TMP/zsh_trigger.out"
assert_rc7 "zsh tmr: exit code preserved" "$TMP/zsh_trigger.out"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
