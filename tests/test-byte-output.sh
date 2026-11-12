#!/usr/bin/env bash
# Byte-level tests for hermes-kbd-rcy wrappers.
# Uses a fake TUI binary + a real pty (script) + grep on the raw bytes:
#   1. trigger case emits the exact two-screen cleanup sequence
#   2. exit code is preserved through the wrapper
#   3. piped stdout emits nothing
#   4. non-matching args emit nothing
# fish cases run with a TEMP XDG_CONFIG_HOME holding the repo's functions, so
# the repo files are exercised even on a machine where the project is already
# installed (and on a clean machine where it is not).
set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

EXPECTED="$(printf '\033[?1049h\033[<u\033[?1049l')"

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

assert_exit() { # $1 label  $2 expected rc  其余参数 = 命令
    local label="$1" want="$2"
    shift 2
    "$@" >/dev/null 2>&1
    local got=$?
    if [ "$got" -eq "$want" ]; then ok "$label"; else bad "$label (exit $got, want $want)"; fi
}

# ---------- fish: functions/hermes.fish ----------
# 隔离: 临时 XDG_CONFIG_HOME 挂载仓库内的 functions,不读取 ~/.config 的已安装副本
mkdir -p "$TMP/fishcfg/fish/functions"
cp "$REPO"/functions/*.fish "$TMP/fishcfg/fish/functions/"

# shellcheck disable=SC2016  # fish 脚本内容里的 $status 不展开
cat > "$TMP/fish_trigger.fish" <<'EOS'
hermes --tui
echo "rc=$status"
EOS
cat > "$TMP/fish_other.fish" <<'EOS'
hermes chat -q hi
echo "rc=$status"
EOS
cat > "$TMP/fish_bare.fish" <<'EOS'
hermes
echo "rc=$status"
EOS

cat > "$TMP/fishrun.sh" <<EOF
#!/usr/bin/env bash
export PATH="$TMP/bin:\$PATH"
export XDG_CONFIG_HOME="$TMP/fishcfg"
exec fish "\$@"
EOF
chmod +x "$TMP/fishrun.sh"

script -qec "$TMP/fishrun.sh $TMP/fish_trigger.fish" /dev/null > "$TMP/fish_trigger.out"
script -qec "$TMP/fishrun.sh $TMP/fish_other.fish" /dev/null > "$TMP/fish_other.out"
script -qec "$TMP/fishrun.sh $TMP/fish_bare.fish" /dev/null > "$TMP/fish_bare.out"
"$TMP/fishrun.sh" "$TMP/fish_trigger.fish" > "$TMP/fish_piped.out" 2>&1

assert_has_seq "fish: --tui emits two-screen cleanup (pty)" "$TMP/fish_trigger.out"
assert_rc7 "fish: exit code preserved" "$TMP/fish_trigger.out"
assert_has_seq "fish: bare invocation emits cleanup (pty)" "$TMP/fish_bare.out"
assert_no_esc "fish: piped stdout stays clean" "$TMP/fish_piped.out"
assert_no_esc "fish: non-tui args emit nothing" "$TMP/fish_other.out"

# --tui 出现在单个参数里不算 TUI 调用（逐元素比较，而不是整串子串匹配）
cat > "$TMP/fish_quoted.fish" <<'EOS'
hermes chat -q "x --tui y"
echo "rc=$status"
EOS
script -qec "$TMP/fishrun.sh $TMP/fish_quoted.fish" /dev/null > "$TMP/fish_quoted.out"
assert_no_esc "fish: quoted arg containing --tui emits nothing" "$TMP/fish_quoted.out"

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

# ---------- bash: bare hermes (display.interface: tui case) ----------
cat > "$TMP/bashrun_bare.sh" <<EOF
#!/usr/bin/env bash
export PATH="$TMP/bin:\$PATH"
source "$REPO/lib/tui-recover.sh"
hermes
echo "rc=\$?"
EOF
chmod +x "$TMP/bashrun_bare.sh"

script -qec "$TMP/bashrun_bare.sh" /dev/null > "$TMP/bash_bare.out"
assert_has_seq "bash hermes: bare invocation emits cleanup (pty)" "$TMP/bash_bare.out"
assert_rc7 "bash hermes: bare invocation preserves exit code" "$TMP/bash_bare.out"

# --tui 出现在单个参数里不算 TUI 调用
cat > "$TMP/bashrun_quoted.sh" <<EOF
#!/usr/bin/env bash
export PATH="$TMP/bin:\$PATH"
source "$REPO/lib/tui-recover.sh"
hermes chat -q "x --tui y"
echo "rc=\$?"
EOF
chmod +x "$TMP/bashrun_quoted.sh"
script -qec "$TMP/bashrun_quoted.sh" /dev/null > "$TMP/bash_quoted.out"
assert_no_esc "bash hermes: quoted arg containing --tui emits nothing" "$TMP/bash_quoted.out"

# tui-recover 函数（README 里那个裸命令）在 bash 下同样可用
cat > "$TMP/bashrun_recover.sh" <<EOF
#!/usr/bin/env bash
source "$REPO/lib/tui-recover.sh"
tui-recover
EOF
chmod +x "$TMP/bashrun_recover.sh"
script -qec "$TMP/bashrun_recover.sh" /dev/null > "$TMP/bash_recover.out"
assert_has_seq "bash tui-recover: emits two-screen cleanup (pty)" "$TMP/bash_recover.out"

# ---------- zsh: same lib ----------
if command -v zsh >/dev/null 2>&1; then
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
else
    echo "SKIP: zsh not installed"
fi

# ---------- bin/tui-recover ----------
script -qec "$REPO/bin/tui-recover" /dev/null > "$TMP/bin_recover.out"
assert_has_seq "bin/tui-recover: emits two-screen cleanup (pty)" "$TMP/bin_recover.out"
assert_exit "bin/tui-recover: unknown option exits 2" 2 "$REPO/bin/tui-recover" --nope
assert_exit "bin/tui-recover: --dry-run rejects extra args" 2 "$REPO/bin/tui-recover" --dry-run bogus

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
