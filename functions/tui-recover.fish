# installed by tui-mode-recovery — https://github.com/Eefung/tui-mode-recovery (remove: install.sh --uninstall)
function tui-recover --description '恢复 TUI 退出后残留的键盘设置(清全屏页)'
    # 进全屏页(alt 屏)弹栈并清零,再回到命令行页
    printf '\e[?1049h\e[=0u\e[?1049l'
end
