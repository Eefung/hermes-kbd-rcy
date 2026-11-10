# installed by tui-mode-recovery — https://github.com/Eefung/tui-mode-recovery (remove: install.sh --uninstall)
function hermes --wraps hermes --description 'hermes + 退出后恢复终端键盘协议状态'
    command hermes $argv
    set -l rc $status
    # hermes --tui 在 alt 屏内 push kitty keyboard protocol(CSI >1u),/quit 不弹
    # (上游 bug NousResearch/hermes-agent#56759,修复 PR #57161 未合并)。
    # kitty 对主屏/alt 屏各维护一份独立的协议栈:shell 提示符(主屏)正常,
    # 但 micro/vim/nano 等走 alt 屏的程序仍把 Ctrl+Q 收成「113;5u」。
    # 实测(kitty CSI ?u 探针):只在主屏发 \e[<u、\e[=0u 无效,必须两屏各清一次。
    # 触发条件:带 --tui,或无参数(display.interface: tui 时裸 hermes 直接进 TUI);
    # 只在 stdout 是 tty 时发序列,管道/脚本调用(hermes chat -q)输出不受污染。
    set -l trigger ''
    if test (count $argv) -eq 0; or string match -q -- '*--tui*' "$argv"
        set trigger yes
    end
    if isatty stdout; and test -n "$trigger"
        printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
    end
    return $rc
end
