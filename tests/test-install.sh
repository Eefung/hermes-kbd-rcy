#!/usr/bin/env bash
# 安装器行为测试：临时 HOME 沙箱里验证安装、幂等、漂移检测、卸载保护。
set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_DATA_HOME="$TMP/data"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
printf '# bashrc\n' > "$HOME/.bashrc"
printf '# zshrc\n' > "$HOME/.zshrc"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
expect() { # $1 描述  $2 命令
    if eval "$2"; then ok "$1"; else bad "$1"; fi
}

LIB="$XDG_DATA_HOME/hermes-kbd-rcy/lib/tui-recover.sh"
FISH="$XDG_CONFIG_HOME/fish/functions"

# 1) 安装
bash "$REPO/install.sh" >/dev/null
expect "安装 fish 函数" "[ -f '$FISH/hermes.fish' ]"
expect "安装稳定路径 lib" "[ -f '$LIB' ]"
expect "rc 块指向稳定路径" "grep -qF 'hermes-kbd-rcy/lib/tui-recover.sh' '$HOME/.bashrc'"
expect "rc 块带可读性守卫" "grep -qF '[ -r ' '$HOME/.bashrc'"

# 2) 幂等：重复安装不重复追加标记块
bash "$REPO/install.sh" >/dev/null
expect "幂等：rc 块只有一份" "[ \"\$(grep -cF '# >>> hermes-kbd-rcy >>>' '$HOME/.bashrc')\" = 1 ]"

# 3) --check 干净状态
expect "--check 干净时退出 0" "bash '$REPO/install.sh' --check >/dev/null 2>&1"

# 4) 漂移检测
printf '\n# drift\n' >> "$LIB"
expect "--check 检测漂移" "! bash '$REPO/install.sh' --check >/dev/null 2>&1"
bash "$REPO/install.sh" >/dev/null   # 刷新

# 5) 用户自建同名文件在卸载时保留
printf 'function hermes; echo mine\nend\n' > "$FISH/hermes.fish"
bash "$REPO/install.sh" --uninstall >/dev/null
expect "卸载保留用户自建 hermes.fish" "[ -f '$FISH/hermes.fish' ]"
expect "卸载删除本项目 tmr.fish" "[ ! -f '$FISH/tmr.fish' ]"
expect "卸载删除 lib" "[ ! -f '$LIB' ]"
expect "卸载删除 rc 块" "! grep -qF '# >>> hermes-kbd-rcy >>>' '$HOME/.bashrc'"

# 6) 反复安装不堆积空行（每次追加的块前空行应在 strip 时回收）
for _ in 1 2 3; do bash "$REPO/install.sh" >/dev/null; done
expect "重复安装不堆空行（rc 内至多一行空行）" \
    "awk '{ if (length == 0) n++ } END { exit !(n <= 1) }' '$HOME/.bashrc'"

# 7) rc 块在、但加载的不是当前 lib → --check 必须报漂移
sed "s|$LIB|/old/gone/lib/tui-recover.sh|g" "$HOME/.bashrc" > "$HOME/.bashrc.stale"
mv "$HOME/.bashrc.stale" "$HOME/.bashrc"
expect "块指向旧路径时 --check 退出 1" "! bash '$REPO/install.sh' --check >/dev/null 2>&1"
bash "$REPO/install.sh" >/dev/null   # 刷新
expect "刷新后 --check 恢复 0" "bash '$REPO/install.sh' --check >/dev/null 2>&1"

# 8) 软链 rc：安装与卸载都不能把链接换成普通文件
printf '# dotfiles bashrc\n' > "$TMP/dotfile-bashrc"
rm -f "$HOME/.bashrc"
ln -s "$TMP/dotfile-bashrc" "$HOME/.bashrc"
bash "$REPO/install.sh" >/dev/null
bash "$REPO/install.sh" >/dev/null
expect "重复安装后 rc 仍是软链" "[ -L '$HOME/.bashrc' ]"
expect "块写进了软链目标" "grep -qF '# >>> hermes-kbd-rcy >>>' '$TMP/dotfile-bashrc'"
bash "$REPO/install.sh" --uninstall >/dev/null
expect "卸载后 rc 仍是软链" "[ -L '$HOME/.bashrc' ]"
expect "卸载后软链目标里块已删除" "! grep -qF '# >>> hermes-kbd-rcy >>>' '$TMP/dotfile-bashrc'"

# 9) 块残缺（缺结束标记）：卸载不动文件，不删标记之后的内容
printf '# top\n# >>> hermes-kbd-rcy >>>\nUSER-LINE-AFTER\n' > "$HOME/.zshrc"
bash "$REPO/install.sh" --uninstall >/dev/null
expect "缺结束标记时卸载保留标记之后的内容" "grep -qF 'USER-LINE-AFTER' '$HOME/.zshrc'"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
