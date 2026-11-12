#!/usr/bin/env bash
# shellcheck shell=bash
# hermes-kbd-rcy — restore terminal mode state after TUI apps exit.
# Source from ~/.bashrc or ~/.zshrc (install.sh adds a guarded block).
#
# Root cause & evidence: https://github.com/Eefung/hermes-kbd-rcy
#
# kitty keeps SEPARATE keyboard-protocol (CSI-u) stacks for the main and the
# alternate screen. TUIs that push `CSI >1u` while INSIDE the alt screen and
# exit without popping leak the ALT stack: the prompt (main screen) looks
# fine, but vi/micro/nano/less (alt screen) receive CSI-u fragments like
# "113;5u". The leak is the alt stack, so the cleanup enters that screen,
# pops once, then returns.

tui_recover_seq() {
    # enter alt -> pop once -> leave alt
    printf '\e[?1049h\e[<u\e[?1049l'
}

# TUI 候选判定：逐个参数比较。整串拼接后再做子串匹配会误中
# `hermes chat -q "… --tui …"` 这类把 --tui 含在单个参数里的非 TUI 调用。
tui_recover_wanted() {
    local a
    for a in "$@"; do
        [ "$a" = "--tui" ] && return 0
    done
    return 1
}

# tui-recover — 只做恢复（与 functions/tui-recover.fish 对应）
tui-recover() {
    tui_recover_seq
}

# tmr <command> [args...] — run a command, restore terminal state after it exits.
tmr() {
    command "$@"
    local rc=$?
    if [ -t 1 ]; then
        tui_recover_seq
    fi
    return $rc
}

# hermes convenience wrapper (matches functions/hermes.fish). Bare `hermes`
# also triggers: with display.interface: tui the bare invocation IS the TUI.
hermes() {
    command hermes "$@"
    local rc=$?
    if [ -t 1 ] && { [ $# -eq 0 ] || tui_recover_wanted "$@"; }; then
        tui_recover_seq
    fi
    return $rc
}
