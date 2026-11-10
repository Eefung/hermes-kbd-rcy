# 实测记录

这个项目的每条结论都来自在真实终端里的测量。本文按「结论 → 怎么测的 → 原始数据」组织，末尾附环境与适用边界，方便对照和复现。

## 方法

探针把 stdin 置为 raw 模式，向 `/dev/tty` 写 `CSI ? u`，终端回 `CSI ? flags u`；再用 `1049h` / `1049l` 切换屏幕，就能分别读到两屏的 flags。之所以写 `/dev/tty` 而不是 stdout，是因为重定向的 stdout 会把转义序列吞进文件，读出来是「全空」的假象。

## 实验 A：hermes --tui 的 push 发生在 alt 屏内

方法：用 `script` 给 `hermes --tui` 一个 pty，把启动字节存盘，统计关键序列首次出现的偏移。

| 序列 | 首次出现偏移 |
|---|---|
| `\e[?1049l`（离开 alt） | 749 |
| `\e[<u`（pop） | 757 |
| `\e[>4m`（复位 modifyOtherKeys） | 761 |
| `\e[?1049h`（进入 alt） | 787 |
| `\e[>1u`（push） | 886 |

启动时先在主屏做了一轮完整清理（前几个序列的形状与上游的输入模式复位序列一致），随后进 alt 屏，再 push——push 落在 alt 栈上。运行期间还观察到 `<u` 与 `>1u` 成对出现（pop-before-push 的重新断言），同样发生在 alt 屏内。

## 实验 B：两屏栈互不继承

| 步骤 | 查询屏 | flags |
|---|---|---|
| 基线 | 主屏 | 0 |
| 主屏 push `>1u` | 主屏 | 1 |
| 进 alt | alt | 0 |
| 退出 alt | 主屏 | 1 |

结论：进 alt 不复制主屏的栈，退 alt 也不重置主屏。

## 实验 C：残留复现，以及单屏清理为何无效

| 步骤 | 查询屏 | flags |
|---|---|---|
| alt 屏内 push `>1u`，退出 alt | alt | 1 |
| 退出之后 | 主屏 | 0 |
| 重新进 alt（= 编辑器的视角） | alt | 1 |
| 从主屏发 `\e[<u`×3 加 `\e[=0u`，再进 alt | alt | 1 |

第三行是症状的全部来源：编辑器切进 alt 屏的那一刻，接手的是一份 flags = 1 的栈。第四行说明从提示符发清理序列永远清不到 alt 栈。

## 实验 D：两屏清理有效

`kbdprobe.py --simulate --fix` 的原始输出：

```
main             0    OK (legacy key encoding)
alt              1    STUCK — alt-screen apps (vi/micro/nano) will see CSI-u fragments like "113;5u"
main_after_fix   0    OK (legacy key encoding)
alt_after_fix    0    OK (legacy key encoding)
```

另外单独验证过双重 push（栈深 2）后用同一序列清理，两屏均回到 0。

## 实验 E：reset 的有效成分

```
rs1=\E]\E\\\Ec
```

`rs1` 结尾的 `ESC c` 是 RIS，全量复位，两屏一起清——所以 `reset` 永远有效，代价是连屏幕一起清掉；定向序列只动键盘协议相关状态。

## 实验 F：包装函数与安装器的行为

`tests/test-byte-output.sh` 用假二进制加真实 pty 核对：pty 下发出的字节与预期序列完全一致、退出码 7 原样透传、管道调用零转义字节、非 TUI 参数零字节。当前 12 个用例全部通过。

安装器行为已固化为 `tests/test-install.sh`（临时 HOME 沙箱）：安装、幂等刷新、`--check` 漂移检测、`--uninstall` 只删带标记的文件与 rc 块、用户自建的同名 `hermes.fish` 不动。探针的应答解析也拆成了纯函数并配了单测（`tests/test_probe.py`，7 个用例），整套检查由 CI 在每次推送时执行。

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
- 「退出时 pop 落在主屏栈」这一条来自源码阅读（unmount 清理块先 `1049l` 再 `<u`；die 路径不发 pop）与上游 issue，没有在运行时逐路径捕获；运行时能直接测到的是「push 在 alt 内」与「退出后 alt 残留」这两端，中间的机制由源码补齐。
