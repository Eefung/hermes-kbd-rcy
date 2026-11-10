# tui-mode-recovery

跑完一个 TUI 程序，回到 shell 一切看着正常，可一进 micro / vim / nano 就发现快捷键全废了：按 Ctrl+Q 不退出，缓冲区里却多出「113;5u」几个字，方向键、Ctrl+C 跟着一起失灵。跑一次 `reset` 能救回来，但没人愿意每次退出 TUI 都手动 reset。

这个仓库把整件事做完整：诊断、清理、自动恢复。坏掉的状态不在应用里，而在终端模拟器内部——所以光等应用修 bug 不一定够，这里直接对终端下手。

## 快速开始

```sh
# 已经被卡住？立刻恢复（不清屏、不动滚动缓冲）
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'

# 装好自动恢复：之后 hermes --tui 一退出就自动清理
./install.sh

# 想看清状态：分别查询主屏与 alt 屏的 flags（0 表示正常）
python3 tools/kbdprobe.py
```

## 问题出在哪

### 终端负责把按键翻译成字节

kitty 键盘协议允许程序改变终端的按键编码方式：`CSI > 1 u` 推入一组 flags（比如 disambiguate 模式），`CSI < u` 弹栈还原。disambiguate 一开，Ctrl+Q 这种「有歧义」的按键就不再发单字节 DC1，而是发 `CSI 113;5u`——113 是 `q` 的码点，5 代表 Ctrl。不认 CSI-u 的编辑器（micro、nano、不少 vim 配置）只当它是普通文本，于是原样打进缓冲区。

### 有人推了，却没弹

`hermes --tui` 认出 kitty 后，会在 **alt 屏内**推入 `CSI > 1 u`。这不是猜测：用 pty 捕获它的启动字节，`\e[?1049h`（进 alt 屏）出现在偏移 787，`\e[>1u` 出现在 886——先换屏，后推栈。退出时这次 push 没有被弹掉：源码里 unmount 清理块先发 `1049l`（离开 alt）再发 `\e[<u`，pop 落在主屏栈上；`die()` / `dieWithCode()` 路径则根本不发 pop。两条路走完，alt 栈都留着 flags = 1。上游 issue 是 [#56759](https://github.com/NousResearch/hermes-agent/issues/56759)，两个修复 PR 至今未合并。

### 于是症状看起来很奇怪

kitty 为**主屏和 alt 屏各维护一份独立的协议栈**，两屏互不继承——这是实测结论，不是推测，逐项数据见 [docs/evidence.md](docs/evidence.md)：

| 你看到的 | 背后发生了什么 |
|---|---|
| 提示符完全正常 | 主屏栈是空的，flags = 0 |
| 只有 micro / vim / nano 坏 | 它们切进 alt 屏，那里的栈残留 flags = 1 |
| 在提示符下发 `\e[<u`、`\e[=0u` 没用 | 只清主屏栈，碰不到 alt 栈 |
| `reset` 一招见效 | kitty 的 terminfo `rs1` 末尾是 RIS（`ESC c`），两屏一起复位 |

## 清理序列

```sh
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
```

| 片段 | 做什么 |
|---|---|
| `1049h`，然后 `<u`×3 加 `=0u` | 进 alt 屏，弹空它的栈并清零 flags |
| `1049l`，然后 `<u`×3 加 `=0u` | 回主屏，再清一遍 |
| `>4m` | 复位 modifyOtherKeys（有些 TUI 也会打开它） |
| `1004l`、`2004l`、`25h` | 关掉 focus 上报与 bracketed paste，恢复光标 |

安全性：对空栈多弹几次是协议规定的无操作；`=0u` 直接清零 flags，与栈深无关；若肇事程序死在 alt 屏里没出来，开头的 `1049h` 是空操作，序列结束仍保证回到主屏。

## 组件

| 路径 | 作用 |
|---|---|
| `functions/hermes.fish` | fish 包装，自动加载：`hermes --tui` 与裸 `hermes` 退出后自动清理 |
| `functions/tmr.fish`、`functions/tui-recover.fish` | 通用包装 `tmr <命令>`；只做恢复的 `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh 版：`tmr` 与 `hermes` 两个函数 |
| `tools/kbdprobe.py` | 探针：按屏查询 `CSI ? u`，可复现可修复，支持 JSON 输出 |
| `tests/test-byte-output.sh` | 字节级测试：假二进制加真实 pty，核对实际发出的字节 |
| `install.sh` | 幂等安装、`--check` 漂移检测、卸载 |
| `bin/tui-recover` | 独立 CLI：不依赖任何 shell 包装也能立刻恢复；`--dry-run` 只打印字节 |
| `docs/evidence.md` | 全部结论的实测记录 |
| `.github/workflows/ci.yml` | CI：shellcheck、fish 语法、单元测试、字节级与安装器测试 |

## 安装与卸载

```sh
./install.sh               # fish 函数进 ~/.config/fish/functions/，
                           # lib 进 ~/.local/share/tui-mode-recovery/lib/，
                           # bash/zsh rc 追加带标记、带可读性守卫的 source 块
./install.sh --check       # 校验已安装副本与仓库一致；漂移时退出码 1
./install.sh --uninstall   # 只删带标记的文件与 rc 块，用户自建的同名函数不动
```

重复执行安全；`git pull` 之后重跑一次即刷新已装副本。

## 使用

```sh
hermes --tui               # 自动恢复（fish / bash / zsh 通用）
tmr <命令> [参数…]        # 任何会弄脏终端状态的 TUI
tui-recover                # 独立 CLI，效果同下面那条 printf（--dry-run 只看字节）
printf '...'               # 手动恢复，等价于上面那条 printf
```

包装只在 stdout 是 tty、且本次调用是 TUI 候选（带 `--tui` 或无参数）时发序列：管道、脚本、`hermes chat -q` 的输出不会被转义字节污染，退出码原样保留。

## 诊断与复现

```sh
python3 tools/kbdprobe.py                   # 分别报告两屏 flags
python3 tools/kbdprobe.py --simulate        # 故意把 alt 栈弄脏，再报告
python3 tools/kbdprobe.py --simulate --fix  # 复现 → 清理 → 复查
python3 tools/kbdprobe.py --json            # 机器可读
```

`--simulate` 就是复现手段：它真的在 alt 屏里 push 一次。完整测量矩阵见 [docs/evidence.md](docs/evidence.md)。

## 测试

```sh
tests/test-byte-output.sh
```

12 个字节级用例（fish / bash / zsh 包装，pty 下逐字节比对）、7 个探针解析单测、11 个安装器用例（沙箱安装、幂等、漂移检测、卸载保护）。CI 在每次推送时跑全套：shellcheck、fish 语法、Python 单测、字节级与安装器测试。fish 用例用临时 `XDG_CONFIG_HOME` 加载仓库里的函数，测的不是本机已安装副本。

## 已知边界

- tmux、ssh kitten 这类中间层自己维护一份协议状态，定向清理可能不够，需要 `reset` 兜底。
- 不支持 CSI-u 的终端会忽略这些序列，包装对它们是无害空操作。
- 上游修复发布后，执行 `./install.sh --uninstall` 移除这层壳即可。

## 参考

- 上游 issue：[#56759](https://github.com/NousResearch/hermes-agent/issues/56759) —— TUI leaves terminal in corrupted state after clean /quit
- 修复 PR：[#57161](https://github.com/NousResearch/hermes-agent/pull/57161)（在 die() / dieWithCode() 里同步 reset）、[#56765](https://github.com/NousResearch/hermes-agent/pull/56765)（栈 pop 之后追加 `CSI = 0 u`）
- [kitty keyboard protocol 规范](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## License

MIT
