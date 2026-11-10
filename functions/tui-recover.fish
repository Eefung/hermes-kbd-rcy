# installed by tui-mode-recovery — https://github.com/Eefung/tui-mode-recovery (remove: install.sh --uninstall)
function tui-recover --description '恢复 TUI 退出后的终端模式状态(kitty CSI-u 主屏/alt 屏双栈清理)'
    # 进 alt 屏弹栈清零 → 回主屏弹栈清零 → 复位 modifyOtherKeys/focus/paste/光标
    printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
end
