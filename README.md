# tui-mode-recovery

跑完 TUI 程序回到 shell，一切看着正常，可一进 micro / vim / nano，Ctrl 开头的快捷键全废：按 Ctrl+Q 不退出，缓冲区里冒出一串「113;5u」，存盘、查找这些组合键也一样失灵（方向键和普通打字不受影响）。`reset` 能救，代价是整个屏幕清空。

这里给一条不清屏的命令，再加一个装一次就自动生效的小工具。

## 快速开始

```sh
# 已经卡住：立即恢复（不清屏、不动滚动缓冲）
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'

# 装一次，之后 hermes --tui 退出自动清理（fish / bash / zsh）
./install.sh

# 看状态：两页各读一次，0 表示正常
python3 tools/kbdprobe.py
```

## 为什么这条命令有效

`hermes --tui` 退出时，会在终端里留下一份没清掉的键盘设置（上游 [#56759](https://github.com/NousResearch/hermes-agent/issues/56759) 未修）。探针读出来是这样两行：

```
main             0    OK (legacy key encoding)
alt              1    STUCK — alt-screen apps (vi/micro/nano) will see CSI-u fragments like "113;5u"
```

命令行这一页（主屏）是 0，全屏程序页（alt 屏）是 1。编辑器切进全屏页，接手的正是这份设置，按键于是变成文本。两页各存各的，互不影响，所以清理要进去清一次、回来再清一次，这就是上面那条命令在做的事。

hermes 退出时自己会恢复 focus 上报、粘贴模式、modifyOtherKeys 和光标（实测：退出块最后是 `1004l → 2004l → 1049l → <u → >4m → 0m → 25h`），唯一没恢复的就是全屏页的键盘设置，因为 `<u` 排在 `1049l` 后面，弹栈落在主屏。命令尾部那几段（`>4m`、`1004l`、`2004l`、`25h`）对正常退出是空操作，只在异常退出（被信号杀掉、崩溃）时起作用。

对空栈多弹几次是无害的；`=0u` 直接清零设置，与栈有多深无关。完整测量记录见 [docs/evidence.md](docs/evidence.md)。

## 组件

| 路径 | 作用 |
|---|---|
| `functions/hermes.fish` | fish 自动加载：`hermes --tui` 与裸 `hermes` 退出后自动清理 |
| `functions/tmr.fish`、`functions/tui-recover.fish` | 通用包装 `tmr <命令>`；只做恢复的 `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh：`tmr` 与 `hermes` 两个函数 |
| `tools/kbdprobe.py` | 探针：按页读 `CSI ? u`，可复现、可修复、可输出 JSON |
| `bin/tui-recover` | 独立 CLI：不需要 shell 包装，`--dry-run` 只看字节 |
| `install.sh` | 安装、`--check` 漂移检测、卸载 |
| `tests/`、`.github/workflows/ci.yml` | 字节级测试、安装器测试、探针单测；CI 每次推送全跑 |

## 安装与卸载

```sh
./install.sh               # 重复执行安全；git pull 之后重跑一次刷新
./install.sh --check       # 校验已装副本与仓库一致
./install.sh --uninstall   # 只删带标记的文件与 rc 块，用户自建的同名函数不动
```

## 使用

```sh
hermes --tui               # 自动恢复（fish / bash / zsh）
tmr <命令> [参数…]        # 任何会弄脏终端状态的 TUI
tui-recover                # 独立 CLI，等价于上面那条 printf
```

包装只在 stdout 是 tty、且调用是 TUI 候选（`--tui` 或无参数）时发序列：管道与脚本输出不会被转义字节污染，退出码原样保留。

## 诊断

```sh
python3 tools/kbdprobe.py                   # 两页各读一次
python3 tools/kbdprobe.py --simulate --fix  # 复现 → 清理 → 复查
python3 tools/kbdprobe.py --json            # 机器可读
```

## 测试

```sh
tests/test-byte-output.sh                              # 12 个字节级用例
tests/test-install.sh                                  # 11 个安装器用例
python3 -m unittest discover -s tests -p 'test_*.py'   # 7 个探针解析单测
```

CI 每次推送跑全套，含 shellcheck 与 fish 语法检查。

## 已知边界

- tmux、ssh kitten 这类中间层自己维护一份状态，定向清理可能不够，需要 `reset` 兜底（它是全量复位，两页一起清，代价是清屏）。
- 不支持 CSI-u 的终端会忽略这些序列，包装对它们是无害空操作。
- 上游修复发布后，执行 `./install.sh --uninstall` 移除这层壳即可。

## 参考

- 上游 issue：[#56759](https://github.com/NousResearch/hermes-agent/issues/56759) —— TUI leaves terminal in corrupted state after clean /quit
- 修复 PR：[#57161](https://github.com/NousResearch/hermes-agent/pull/57161)、[#56765](https://github.com/NousResearch/hermes-agent/pull/56765)（均未合并）
- [kitty keyboard protocol 规范](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## License

MIT
