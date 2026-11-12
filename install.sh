#!/usr/bin/env bash
# hermes-kbd-rcy installer.
#   install.sh               install / refresh (re-run after git pull)
#   install.sh --check       verify installed copies match the repo; exit 1 on drift
#   install.sh --uninstall   remove everything this script installed
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FISH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hermes-kbd-rcy"
LIB_DST="$DATA_DIR/lib/tui-recover.sh"
FISH_FILES=(tui-recover.fish tmr.fish hermes.fish)
MARKER="# >>> hermes-kbd-rcy >>>"
MARKER_END="# <<< hermes-kbd-rcy <<<"
RCS=("$HOME/.bashrc" "$HOME/.zshrc")

usage() {
    cat <<'EOF'
用法: install.sh [选项]

  （无参数）      安装 / 刷新：fish 函数复制到 fish 配置目录，lib 复制到
                  ~/.local/share/hermes-kbd-rcy/，bash/zsh rc 追加带标记的 source 块
  --check         校验已安装副本与仓库一致；缺失或过期时退出码为 1
  --uninstall     只删除带本项目标记的文件与 rc 块，用户自建的同名函数不动
  -h, --help      显示本帮助
EOF
}

strip_rc_block() {  # $1 = rc 文件；存在标记块则整体删除
    local rc="$1"
    grep -qF "$MARKER" "$rc" || return 0
    awk -v s="$MARKER" -v e="$MARKER_END" '
        $0 == s { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip
    ' "$rc" > "$rc.tmr.tmp"
    mv "$rc.tmr.tmp" "$rc"
}

rc_block() {
    cat <<EOF
$MARKER
# hermes-kbd-rcy: restore terminal mode state after TUI exit
# (kitty CSI-u main/alt screen stacks; see https://github.com/Eefung/hermes-kbd-rcy)
[ -r "$LIB_DST" ] && . "$LIB_DST"
$MARKER_END
EOF
}

check() {
    local drift=0 f rc
    for f in "${FISH_FILES[@]}"; do
        if [ ! -f "$FISH_DIR/$f" ]; then
            echo "missing: $FISH_DIR/$f"
            drift=1
        elif ! cmp -s "$REPO_DIR/functions/$f" "$FISH_DIR/$f"; then
            echo "drift:   $FISH_DIR/$f（重新运行 ./install.sh 刷新）"
            drift=1
        fi
    done
    if [ ! -f "$LIB_DST" ]; then
        echo "missing: $LIB_DST"
        drift=1
    elif ! cmp -s "$REPO_DIR/lib/tui-recover.sh" "$LIB_DST"; then
        echo "drift:   $LIB_DST（重新运行 ./install.sh 刷新）"
        drift=1
    fi
    for rc in "${RCS[@]}"; do
        [ -f "$rc" ] || continue
        if ! grep -qF "$MARKER" "$rc"; then
            echo "missing: rc 块 in $rc"
            drift=1
        fi
    done
    if [ "$drift" -eq 0 ]; then
        echo "已安装副本与仓库一致。"
    fi
    exit "$drift"
}

uninstall() {
    local f rc
    for f in "${FISH_FILES[@]}"; do
        [ -f "$FISH_DIR/$f" ] || continue
        # 只删除带本项目标记的文件，避免误删用户自建的同名 fish 函数
        if grep -qF 'hermes-kbd-rcy' "$FISH_DIR/$f" 2>/dev/null; then
            rm -f "$FISH_DIR/$f"
            echo "removed fish function: $FISH_DIR/$f"
        else
            echo "skipped (not installed by this project): $FISH_DIR/$f"
        fi
    done
    if [ -f "$LIB_DST" ]; then
        rm -f "$LIB_DST"
        echo "removed lib: $LIB_DST"
    fi
    rmdir "$DATA_DIR/lib" "$DATA_DIR" 2>/dev/null || true
    for rc in "${RCS[@]}"; do
        [ -f "$rc" ] || continue
        if grep -qF "$MARKER" "$rc"; then
            strip_rc_block "$rc"
            echo "removed rc block: $rc"
        fi
    done
    echo "uninstalled。新开一个 shell 即生效。"
    exit 0
}

do_install() {
    local f rc
    mkdir -p "$FISH_DIR" "$(dirname "$LIB_DST")"
    for f in "${FISH_FILES[@]}"; do
        cp "$REPO_DIR/functions/$f" "$FISH_DIR/$f"
        echo "installed fish function: $FISH_DIR/$f"
    done
    cp "$REPO_DIR/lib/tui-recover.sh" "$LIB_DST"
    echo "installed lib: $LIB_DST"
    for rc in "${RCS[@]}"; do
        [ -f "$rc" ] || continue
        # 每次安装都重写标记块：旧版本曾把 source 指向克隆目录，这里顺带迁移
        strip_rc_block "$rc"
        printf '\n' >> "$rc"
        rc_block >> "$rc"
        echo "wrote rc block: $rc"
    done
    echo
    echo "done。新开一个 shell，然后运行：hermes --tui（退出时自动恢复）。"
}

case "${1:-}" in
    --uninstall) uninstall ;;
    --check) check ;;
    -h|--help) usage; exit 0 ;;
    "") do_install ;;
    *) usage >&2; exit 2 ;;
esac
