# installed by hermes-kbd-rcy — https://github.com/Eefung/hermes-kbd-rcy (remove: install.sh --uninstall)
function tui-recover --description '恢复 TUI 退出后残留的键盘设置(清全屏页)'
    # 进全屏页(alt 屏)弹一次栈,再回到命令行页
    printf '\e[?1049h\e[<u\e[?1049l'
end
