#!/usr/bin/env bash
# tui-mode-recovery installer: fish functions + bash/zsh rc block. Idempotent.
#   install.sh            install
#   install.sh --uninstall  remove everything this script installed
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FISH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish/functions"
FISH_FILES=(tui-recover.fish tmr.fish hermes.fish)
MARKER="# >>> tui-mode-recovery >>>"
MARKER_END="# <<< tui-mode-recovery <<<"
RCS=("$HOME/.bashrc" "$HOME/.zshrc")

uninstall() {
    for f in "${FISH_FILES[@]}"; do
        [ -f "$FISH_DIR/$f" ] || continue
        # 只删除带本项目标记的文件,避免误删用户自建的同名 fish 函数
        if grep -qF 'tui-mode-recovery' "$FISH_DIR/$f" 2>/dev/null; then
            rm -f "$FISH_DIR/$f"
            echo "removed fish function: $FISH_DIR/$f"
        else
            echo "skipped (not installed by this project): $FISH_DIR/$f"
        fi
    done
    for rc in "${RCS[@]}"; do
        [ -f "$rc" ] || continue
        if grep -qF "$MARKER" "$rc"; then
            sed -i "/${MARKER}/,/${MARKER_END}/d" "$rc"
            echo "removed rc block: $rc"
        fi
    done
    echo "uninstalled. restart your shell (fish picks up automatically)."
    exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

# --- fish ---
mkdir -p "$FISH_DIR"
for f in "${FISH_FILES[@]}"; do
    cp "$REPO_DIR/functions/$f" "$FISH_DIR/$f"
    echo "installed fish function: $FISH_DIR/$f"
done

# --- bash / zsh ---
for rc in "${RCS[@]}"; do
    [ -f "$rc" ] || continue
    if grep -qF "$MARKER" "$rc"; then
        echo "rc block already present: $rc (skipped)"
        continue
    fi
    cat >> "$rc" <<EOF

$MARKER
# tui-mode-recovery: restore terminal mode state after TUI exit
# (kitty CSI-u main/alt screen stacks; see https://github.com/Eefung/tui-mode-recovery)
source "$REPO_DIR/lib/tui-recover.sh"
$MARKER_END
EOF
    echo "added rc block: $rc"
done

echo
echo "done. open a new shell, then run: hermes --tui  (recovery is automatic on exit)"
