# tui-mode-recovery

TUI 程序退出后,终端可能带着残留的键盘协议状态继续工作:shell 提示符一切正常,但 micro / vim / nano 里按 Ctrl+Q 会插入字面量 `113;5u`,方向键、Ctrl+C/X 也全部失灵——只有跑一次 `reset` 才能救回来。

本仓库处理的是**根因**,不是给 `reset` 换个包装:泄漏的是 kitty keyboard protocol 的协议栈,**主屏和 alt 屏各有一份**,而肇事程序把 push 落在了 alt 屏上;任何只清理当前屏的做法都碰不到它。

## 30 秒上手

```sh
# 1) 已卡住的终端:立即恢复(不清屏、不动滚动缓冲)
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'

# 2) 永久方案:安装自动恢复(fish / bash / zsh,幂等)
./install.sh

# 3) 诊断:分别查询主屏与 alt 屏当前 flags
python3 tools/kbdprobe.py
```

## 为什么会坏

### 协议背景

kitty keyboard protocol 让程序向终端**推送**一组键盘编码 flags(`CSI > 1 u`,如 disambiguate 模式),用 `CSI < u` 弹栈恢复。disambiguate 生效后,Ctrl+Q 无法再用旧的单字节编码(DC1 / 0x11),终端改发 `CSI 113;5u`:113 是字母 `q` 的码点,5 是 Ctrl 修饰位。不认识 CSI-u 的程序(micro、nano、部分 vim 配置)就把这串当作普通文本插入。

### 罪魁:一条没有配对的 push

`hermes --tui`(Ink TUI)检测到 kitty 在它的扩展键白名单里,**在 alt 屏内**发送 `CSI > 1 u`。而 `/quit` 的退出路径(`die()` / `dieWithCode()`)没有同步弹出——`CSI < u` 压根没发出去。上游 issue 见 [hermes-agent#56759](https://github.com/NousResearch/hermes-agent/issues/56759),修复 PR [#57161](https://github.com/NousResearch/hermes-agent/pull/57161)、[#56765](https://github.com/NousResearch/hermes-agent/pull/56765) 截至本文写作时仍未合并。

### 为什么只有编辑器坏、提示符好好的

kitty 按规范为**主屏和 alt 屏各维护一份独立的键盘协议栈**,两屏互不继承(实测数据见 [docs/probe-evidence.md](docs/probe-evidence.md))。肇事程序的 push 落在 alt 栈,于是:

| 你看到的 | 实际状态 |
|---|---|
| shell 提示符完全正常 | 主屏栈是空的,flags = 0 |
| 一进 micro / vim / nano 快捷键全变文本 | 它们切换进的 alt 屏残留 flags = 1 |
| 在提示符下发 `\e[<u`、`\e[=0u` 清理,毫无效果 | 只作用于主屏,碰不到 alt 栈 |
| `reset` 总能修好 | kitty 的 terminfo `rs1` 结尾是 RIS(`ESC c`),把两屏全部状态一起复位 |

## 清理序列

```sh
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
```

逐段拆解:

| 片段 | 作用 |
|---|---|
| `1049h` → `<u`×3 + `=0u` | 进入 alt 屏,弹空它的协议栈并清零 flags |
| `1049l` → `<u`×3 + `=0u` | 回到主屏,再清一遍 |
| `>4m` | 复位 modifyOtherKeys(部分 TUI 会顺手打开) |
| `1004l` / `2004l` / `25h` | 关闭 focus 上报、bracketed paste,恢复光标 |

安全性论证:

- 对空栈的多余 pop 是规范定义的无害 no-op;`=0u` 直接清零 flags,与栈深度无关,所以任意深度的残留都能清掉。
- 若肇事程序死在 alt 屏里没出来,开头的 `1049h` 是 no-op,序列结束时仍保证回到主屏。

## 仓库内容

| 路径 | 作用 |
|---|---|
| `functions/hermes.fish` | fish 包装:自动加载,`hermes --tui` 与裸 `hermes`(覆盖 `display.interface: tui`)退出后恢复 |
| `functions/tmr.fish` / `tui-recover.fish` | fish 通用包装 `tmr <命令>`,以及只做恢复的 `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh 版:`tmr` 与 `hermes` 两个函数 |
| `tools/kbdprobe.py` | 探针:按屏查询 `CSI ? u` flags,可复现残留、可执行修复、可输出 JSON |
| `tests/test-byte-output.sh` | 字节级测试:假二进制 + 真实 pty,校验实际发出的字节、退出码、管道静默 |
| `install.sh` | 幂等安装 / 卸载 |
| `docs/probe-evidence.md` | 探针原始测量数据与解读 |

## 安装与卸载

```sh
./install.sh               # fish:复制函数到 ~/.config/fish/functions/
                           # bash/zsh:向已有 rc 文件追加带标记的 source 块
./install.sh --uninstall   # 只删除带本项目标记的文件与 rc 块
```

- 安装幂等,重复执行安全;新开一个 shell 后生效。
- 卸载有保护:不带标记的同名 fish 函数(用户自建)不会被删。

## 使用

```sh
hermes --tui               # 自动:退出后立即恢复(fish / bash / zsh)
tmr <命令> [参数...]       # 通用:任何会污染终端状态的 TUI 程序
printf '...'               # 手动:已卡住的终端里直接执行上面的清理序列
```

包装函数只在 **stdout 是 tty** 且本次调用是 TUI 候选(`--tui`,或无参数)时发送序列:管道与脚本场景(`hermes chat -q`)输出不受污染,退出码原样保留。

## 探针

```sh
python3 tools/kbdprobe.py                 # 报告主屏 / alt 屏 flags
python3 tools/kbdprobe.py --simulate      # 在 alt 屏复现残留(故意弄脏),再报告
python3 tools/kbdprobe.py --simulate --fix  # 复现 → 修复 → 复查
python3 tools/kbdprobe.py --json          # 机器可读输出
```

探针通过 `CSI ? u` 查询、读取终端应答 `CSI ? flags u`,并借助 `1049h` / `1049l` 分别查询两屏。`--simulate` 会真的弄脏 alt 屏栈(这正是复现手段),请配合 `--fix` 使用。

## 测试

```sh
tests/test-byte-output.sh
```

12 个用例,覆盖:两屏序列字节精确匹配、退出码保留、管道静默、非 TUI 参数静默、裸 `hermes` 触发、bash / fish / zsh 三种包装。fish 用例使用临时 `XDG_CONFIG_HOME`,保证测的是仓库内的函数而不是已安装副本。

## 已知边界

- tmux、kitty 的 ssh kitten 这类自己维护一份协议状态的中间层,定向序列可能不够,仍需 `reset` 兜底。
- 不支持 CSI-u 的终端会忽略这些序列,包装函数对它们是无害 no-op。
- 上游修复合并后(预计随 hermes-agent v0.24.0),执行 `./install.sh --uninstall` 即可移除。

## 参考

- 上游 bug:[hermes-agent#56759](https://github.com/NousResearch/hermes-agent/issues/56759) —— TUI leaves terminal in corrupted state after clean /quit
- 修复 PR:[#57161](https://github.com/NousResearch/hermes-agent/pull/57161)(die()/dieWithCode() 补同步 reset)、[#56765](https://github.com/NousResearch/hermes-agent/pull/56765)(栈 pop 后追加 `CSI = 0 u`)
- [kitty keyboard protocol 规范](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## License

MIT
