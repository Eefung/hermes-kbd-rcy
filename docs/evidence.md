# 实测记录

每条结论都来自真实终端里的测量。本文按「怎么测 → 原始数据」组织，环境与边界附在末尾。

## 方法

探针把 stdin 置为 raw，向 `/dev/tty` 写 `CSI ? u`，终端回 `CSI ? flags u`；用 `1049h` / `1049l` 切换屏幕，分别读两页。写 `/dev/tty` 而不是 stdout，是因为重定向的 stdout 会把转义序列吞进文件，读出来是「全空」的假象。

## 一、push 发生在全屏页

用 `script` 给 `hermes --tui` 一个 pty，把启动字节存盘，统计关键序列首次出现的偏移：

| 序列 | 首次出现偏移 |
|---|---|
| `\e[?1049l`（离开 alt） | 749 |
| `\e[<u`（pop） | 757 |
| `\e[>4m`（复位 modifyOtherKeys） | 761 |
| `\e[?1049h`（进入 alt） | 787 |
| `\e[>1u`（push） | 886 |

启动时先在主屏做了一轮清理，随后进 alt 屏，再 push：设置落在 alt 页上。运行期间还能看到 `<u` 与 `>1u` 成对出现（pop-before-push 的重新断言），同样发生在 alt 页内。

### 退出路径实测（/quit）

在 pty 里跑 `hermes --tui`，输入 `/quit`，捕获退出字节。最后一块复位序列是：

```
… 1004l → 2004l → 1049l → <u → >4m → 0m → 25h
```

由此得到两个确定结论：

- focus 上报、bracketed paste、modifyOtherKeys、光标，hermes 退出时自己恢复了，修复序列尾部那几段对正常退出是空操作；
- 它唯一没恢复的是 alt 页的键盘设置：`<u` 排在 `1049l` 之后，弹栈落在主屏，alt 页永远留着（与实验二的残留一致）。

## 二、两页互不继承，残留只落在全屏页

| 步骤 | 查询页 | flags |
|---|---|---|
| 基线 | 主屏 | 0 |
| 主屏 push `>1u` | 主屏 | 1 |
| 进 alt | alt | 0 |
| 退出 alt | 主屏 | 1 |
| alt 页内 push `>1u`，退出 | alt | 1 |
| 退出之后 | 主屏 | 0 |
| 再进 alt（编辑器的视角） | alt | 1 |
| 从主屏执行 `\e[<u`×3 加 `\e[=0u`，再进 alt | alt | 1 |

前三行说明两页各存各的；后四行是症状的全部来源：编辑器切进 alt 页，接手的是一份 flags = 1 的设置，而从主屏执行的清理只作用于主屏。

## 三、两页清理有效

`kbdprobe.py --simulate --fix` 的原始输出：

```
main             0    OK (legacy key encoding)
alt              1    STUCK — alt-screen apps (vi/micro/nano) will see CSI-u fragments like "113;5u"
main_after_fix   0    OK (legacy key encoding)
alt_after_fix    0    OK (legacy key encoding)
```

另验证过双重 push（栈深 2）后用同一序列清理，两页均回到 0。

### 候选写法实测

同一残留状态下，从主屏依次试几种更短的写法：

| 候选序列 | 主屏 | alt 页 |
|---|---|---|
| 当前序列（两页各弹 3 次 + `=0u`，带尾部复位） | 0 | 0 |
| 只 `=0u`，每页一次 | 0 | 0 |
| 只 `<u`，每页一次 | 0 | 0 |
| 单次 pop + `=0u`，每页一次 | 0 | 0 |
| 只在主屏清 | 0 | 1 |

kitty 上最简可用的是 `\e[?1049h\e[=0u\e[?1049l\e[=0u`。仓库保留「弹栈 + `=0u` + 尾部复位」的写法，是因为不同终端对这两种做法的支持程度不一样（弹栈更普遍，`=0u` 更直接），双保险外加清理 TUI 可能顺带打开的 modifyOtherKeys、focus 上报与 bracketed paste。

## 四、包装与安装器的行为

`tests/test-byte-output.sh` 用假二进制加真实 pty 核对：pty 下发出的字节与预期序列完全一致、退出码 7 原样透传、管道调用零转义字节、非 TUI 参数零字节。

`tests/test-install.sh` 在临时 HOME 沙箱里核对：安装、幂等刷新、`--check` 漂移检测、`--uninstall` 只删带标记的文件与 rc 块、用户自建的同名 `hermes.fish` 不动。探针的应答解析拆成纯函数并配了单测（`tests/test_probe.py`）。整套检查由 CI 在每次推送时执行。

## 环境

| 项 | 值 |
|---|---|
| 系统 | CachyOS，内核 7.3.3-1-cachyos |
| 会话 | KDE Plasma，Wayland |
| 终端 | kitty 0.49.2 |
| shell | fish 4.9.3 |
| 肇事程序 | hermes-agent v0.23.0（2026.9.24） |
| 日期 | 2026-11-10 |

## 边界

- 以上测量都在 kitty 本体完成；tmux、ssh kitten 这类中间层各自维护状态副本，未逐项测量，遇到时以 `reset` 兜底。
- 「退出时 pop 落在主屏」这一条来自源码阅读（unmount 清理块先 `1049l` 再 `<u`；die 路径不发 pop）与上游 issue，没有在运行时逐路径捕获；运行时直测的是「push 在 alt 内」与「退出后 alt 残留」两端。
