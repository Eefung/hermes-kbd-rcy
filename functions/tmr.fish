function tmr --description '运行命令,退出后自动恢复终端模式状态'
    if test (count $argv) -eq 0
        echo "tmr: 用法:tmr <命令> [参数...]" >&2
        return 2
    end
    command $argv
    set -l rc $status
    if isatty stdout
        tui-recover
    end
    return $rc
end
