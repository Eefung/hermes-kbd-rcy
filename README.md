# TUI 键盘残留恢复

跑完 TUI 程序回到 shell，一切看着正常，可一进 micro / vim / nano，Ctrl 开头的快捷键全废：按 Ctrl+Q 不退出，缓冲区里冒出一串「113;5u」，存盘、查找这些组合键也一样失灵（方向键和普通打字不受影响）。

这里给一条不清屏的命令，再加一个装一次就自动生效的小工具。

## 原理

`hermes --tui` 退出时，会在终端里留下一份没清掉的键盘设置（上游 [#56759](https://github.com/NousResearch/hermes-agent/issues/56759) 未修）。探针读出来是这样两行：

```text
main             0    OK (legacy key encoding)
alt              1    STUCK — alt-screen apps (vi/micro/nano) will see CSI-u fragments like "113;5u"
```

命令行这一页（主屏）是 0，全屏程序页（alt 屏）是 1。编辑器切进全屏页，接手的正是这份设置，按键于是变成文本。

hermes 退出时自己会恢复 focus 上报、粘贴模式、modifyOtherKeys 和光标，唯一没恢复的就是全屏页的键盘设置，因为 `<u` 排在 `1049l` 后面，弹栈落在主屏。所以命令只做一件事：进全屏页弹一次，再回来——和 hermes 自己的退出清理同一种机制，一次 `<u>` 即恢复。见[实测记录](docs/evidence.md)。

## 安装

```sh
./install.sh               # 重复执行安全；git pull 之后重跑一次刷新
./install.sh --check       # 校验已装副本与仓库一致
./install.sh --uninstall   # 只删带标记的文件与 rc 块，用户自建的同名函数不动
```

## 用法

```sh
printf '\e[?1049h\e[<u\e[?1049l'   # 已经卡住：立即恢复（不清屏、不动滚动缓冲）
hermes --tui                       # 装过之后退出自动恢复（fish / bash / zsh）
tmr <命令> [参数…]                 # 任何会弄脏终端状态的 TUI
tui-recover                        # 独立 CLI，等价于上面那条 printf
python3 tools/kbdprobe.py          # 看状态：两页各读一次，0 表示正常
python3 tools/kbdprobe.py --simulate --fix   # 复现 → 清理 → 复查
python3 tools/kbdprobe.py --json   # 机器可读
```

包装只在 stdout 是 tty、且调用是 TUI 候选（`--tui` 或无参数）时发序列：管道与脚本输出不会被转义字节污染，退出码原样保留。

## 问题

### tmux、ssh kitten 下也管用吗？

不一定。这类中间层自己维护一份状态，定向清理可能不够，需要 `reset` 兜底——它是全量复位，两页一起清，代价是清屏。

### 老版本 hermes（v0.18）为什么不修好？

v0.18 会累积多条 push，一次 `<u>` 不够，不在覆盖范围。拿 `=0u` 顶替也不行：它只改 flags，栈里的记录仍在，下一次 `<u>` 会原样弹回来（见[实测记录](docs/evidence.md)）。

### 终端不支持 CSI-u 会怎样？

这些序列被忽略，包装对它是无害空操作。

### 异常退出（信号、崩溃）也清理吗？

不清理。包装只在正常退出路径发序列。

### 上游修好后还要留着吗？

不用，`./install.sh --uninstall` 移除这层壳即可。

## 开发

```sh
tests/test-byte-output.sh                              # 18 个字节级用例
tests/test-install.sh                                  # 19 个安装器用例
python3 -m unittest discover -s tests -p 'test_*.py'   # 7 个探针解析单测
```

## 文档

| 路径 | 作用 |
| --- | --- |
| `functions/hermes.fish` | fish 自动加载：`hermes --tui` 与裸 `hermes` 退出后自动清理 |
| `functions/tmr.fish`、`functions/tui-recover.fish` | 通用包装 `tmr <命令>`；只做恢复的 `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh：`tmr`、`hermes`、`tui-recover` 三个函数 |
| `tools/kbdprobe.py` | 探针：按页读 `CSI ? u`，可复现、可修复、可输出 JSON |
| `bin/tui-recover` | 独立 CLI：不需要 shell 包装，`--dry-run` 只看字节 |
| `install.sh` | 安装、`--check` 漂移检测、卸载 |
| `tests/` | 字节级用例、安装器用例、探针解析单测 |
| `.github/workflows/ci.yml` | 每次推送全跑上面三套测试，外加 shellcheck 与 fish 语法检查 |
| `docs/evidence.md` | 实测记录：push 落在哪页、两页栈是否互继承、栈深、`=0u` 的实际行为 |

## 参考

- 上游 issue：[#56759](https://github.com/NousResearch/hermes-agent/issues/56759) —— TUI leaves terminal in corrupted state after clean /quit
- 修复 PR：[#57161](https://github.com/NousResearch/hermes-agent/pull/57161)、[#56765](https://github.com/NousResearch/hermes-agent/pull/56765)（均未合并）
- [kitty keyboard protocol 规范](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## 许可

MIT，见 [`LICENSE`](LICENSE)。
