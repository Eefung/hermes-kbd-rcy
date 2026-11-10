function hermes --wraps hermes --description 'hermes + 在 --tui 退出后恢复终端键盘协议状态'
    command hermes $argv
    set -l rc $status
    # hermes --tui 在 alt 屏内 push kitty keyboard protocol(CSI >1u),/quit 不弹
    # (上游 bug NousResearch/hermes-agent#56759,修复 PR #57161 未合并)。
    # kitty 对主屏/alt 屏各维护一份独立的协议栈:shell 提示符(主屏)正常,
    # 但 micro/vim/nano 等走 alt 屏的程序仍把 Ctrl+Q 收成「113;5u」。
    # 实测(kitty CSI ?u 探针):只在主屏发 \e[<u、\e[=0u 无效,必须两屏各清一次。
    # 顺序:1049h 进 alt 清栈清 flags → 1049l 回主屏清 → 复位 modifyOtherKeys/focus/paste/光标。
    if isatty stdout; and string match -q -- '*--tui*' "$argv"
        printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
    end
    return $rc
end
