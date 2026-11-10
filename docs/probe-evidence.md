# 探针实测证据

方法:`tools/kbdprobe.py` 的原理——在 kitty 内把 stdin 置为 raw 模式,发送 `CSI ?u`,从 tty 输入读回应答 `CSI ? flags u`,即可查询**当前所在屏**的 CSI-u flags;配合 `1049h` / `1049l` 可分别查询主屏与 alt 屏(kitty 对两屏维护独立的协议栈)。

环境:kitty(Wayland,CachyOS),2026-11-10。

## 复现与定位(旧的单屏清理为何无效)

| 步骤 | 查询结果 |
|---|---|
| 主屏基线 | flags = 0 |
| 主屏 push `>1u`(顺序 A:先 push 后进 alt)| 1 |
| 进 alt 屏 | **0**(两屏栈独立,不继承)|
| 退出 alt | 主屏仍 1 |
| 主屏发旧清理 `\e[<u×3 + \e[=0u` | 0(主屏栈被清掉)|
| alt 屏内 push `>1u`(顺序 B:**hermes TUI 的实际顺序**)| 1 |
| 退出 alt | 主屏 0 |
| 重进 alt(= micro/vim 的视角)| **1——残留复现** |
| 主屏发旧清理后再进 alt | **仍是 1——证明主屏-only 清理无效** |
| 在 alt 屏内直接清 | **0** |
| RIS(`\ec`,即 `reset` 的 rs1 内容)后进 alt | 0——解释了为什么 `reset` 总有效 |

## 修复验证(两屏清理序列)

清理序列:`1049h → \e[<u×3 + \e[=0u → 1049l → \e[<u×3 + \e[=0u → >4m → 1004l → 2004l → 25h`

| 场景 | 清理后 alt 屏 | 清理后主屏 |
|---|---|---|
| alt 屏内 push ×1 后退出 | 0 | 0 |
| alt 屏内 push ×2 后退出 | 0 | 0 |

## 结论

- kitty 的 CSI-u 栈按屏隔离:push 发生在哪一屏,残留就留在哪一屏的栈里。
- hermes --tui 先挂 alt 屏再设 raw 模式,push 落在 **alt 栈**;`/quit` 退出路径不弹(上游 [hermes-agent#56759](https://github.com/NousResearch/hermes-agent/issues/56759))。
- 修复必须两屏各清一次;只在当前屏做,对另一屏的栈没有任何作用。
- 附加发现:kitty 对 xterm `modifyOtherKeys`(`CSI >4;2m`)的实现不映射到 CSI-u flags(查询结果保持 0),所以 `113;5u` 症状本身来自协议栈而非 modifyOtherKeys。
