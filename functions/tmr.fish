# installed by hermes-kbd-rcy — https://github.com/Eefung/hermes-kbd-rcy (remove: install.sh --uninstall)
function tmr --description '运行命令,退出后自动恢复终端模式状态'
    if test (count $argv) -eq 0
        echo "tmr: 用法: tmr <命令> [参数...]" >&2
        return 2
    end
    command $argv
    set -l rc $status
    if isatty stdout
        # 内联同一条序列,不依赖 functions/tui-recover.fish:只装这一个文件也能用
        printf '\e[?1049h\e[<u\e[?1049l'
    end
    return $rc
end
