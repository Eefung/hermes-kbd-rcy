# installed by tui-mode-recovery — https://github.com/Eefung/tui-mode-recovery (remove: install.sh --uninstall)
function hermes --wraps hermes --description 'hermes + 退出后恢复终端键盘协议状态'
    command hermes $argv
    set -l rc $status
    # hermes --tui 在全屏页(alt 屏)里 push 键盘协议设置,/quit 时先离开全屏页
    # 再发弹栈,pop 落在命令行页上,全屏页于是永远留着设置(上游 #56759 未修)。
    # 实测退出块:1004l → 2004l → 1049l → <u → >4m → 0m → 25h;
    # focus、粘贴、modifyOtherKeys、光标 hermes 自己会恢复,唯一漏掉的是全屏页。
    # 所以只需进全屏页弹栈并清零,再回到命令行页。主屏全程为 0,不用清。
    # 触发条件:带 --tui,或无参数(display.interface: tui 时裸 hermes 直接进 TUI);
    # 只在 stdout 是 tty 时发序列,管道/脚本调用(hermes chat -q)输出不受污染。
    set -l trigger ''
    if test (count $argv) -eq 0; or string match -q -- '*--tui*' "$argv"
        set trigger yes
    end
    if isatty stdout; and test -n "$trigger"
        printf '\e[?1049h\e[=0u\e[?1049l'
    end
    return $rc
end
