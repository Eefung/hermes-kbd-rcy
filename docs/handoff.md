# 项目上下文摘要

给后续维护者与新会话的交接文档：问题、已验证的事实、当前实现、上游状态，一页读完。完整测量数据见 [evidence.md](evidence.md)。

## 问题与修复

`hermes --tui` 退出后，全屏页（alt 屏）的键盘设置没有恢复，编辑器里 Ctrl 快捷键全变文本（`113;5u`）。

修复只有一条命令：

```sh
printf '\e[?1049h\e[<u\e[?1049l'
```

进全屏页、弹一次栈、回来。

## 已验证的事实（kitty 0.49.2 / hermes v0.23.0）

- 启动顺序：`\e[?1049h`（偏移 787）先于 `\e[>1u`（886），push 落在全屏页。
- 退出块：`1004l → 2004l → 1049l → <u → >4m → 0m → 25h`。focus 上报、粘贴模式、modifyOtherKeys、光标都由 hermes 自己恢复；唯一漏掉的是全屏页键盘设置，因为 `<u` 在 `1049l` 之后，弹到了命令行页。
- 两页各存一份栈、互不继承：退出后 main = 0、alt = 1；从主屏清理不影响 alt。
- 栈深：v0.23.0 退出时为 1，单次 `<u>` 足够；深度 2 时单次弹栈失效，需要 `=0u`（v0.18 会累积 push）。

## 实现

| 路径 | 作用 |
|---|---|
| `functions/hermes.fish` | fish 自动加载：`hermes --tui` 与裸 `hermes` 退出后发恢复序列 |
| `functions/tmr.fish`、`functions/tui-recover.fish` | 通用包装 `tmr <命令>`；只做恢复的 `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh：`tmr` 与 `hermes` |
| `tools/kbdprobe.py` | 探针：按页读 `CSI ? u`，`--simulate` 复现、`--fix` 修复、`--json` |
| `bin/tui-recover` | 独立 CLI，`--dry-run` 只打印字节 |
| `install.sh` | 安装、`--check` 漂移检测、卸载 |
| `tests/` | 字节级 12、安装器 11、探针解析 7；CI 全跑 |

## 验证方式

```sh
python3 tools/kbdprobe.py --simulate --fix   # 应显示：修复后 main 0 / alt 0
tests/test-byte-output.sh                    # 12/12
tests/test-install.sh                        # 11/11
./install.sh --check                         # 已装副本与仓库一致
```

## 上游状态

- issue [#56759](https://github.com/NousResearch/hermes-agent/issues/56759) 仍 open。
- PR [#57161](https://github.com/NousResearch/hermes-agent/pull/57161)、[#56765](https://github.com/NousResearch/hermes-agent/pull/56765) open 但**都修不好**：复位串与退出块的 pop 都发生在离开全屏页之后。
- 本仓库提交的修复 PR：[#152683](https://github.com/NousResearch/hermes-agent/pull/152683)（ink.tsx 在 `EXIT_ALT_SCREEN` 前弹栈；terminalModes.ts 把 `<u` + `=0u` 移到 `1049l` 前；新增顺序断言测试）。
- issue 下的说明评论：[#issuecomment-6769924919](https://github.com/NousResearch/hermes-agent/issues/56759#issuecomment-6769924919)。
- 上游合并后执行 `./install.sh --uninstall` 移除包装。

## 已定决策

- 只清全屏页：命令行页实测恒为 0，清它是空操作。
- 用单次 `<u>`，与 hermes 自身退出清理一致；深栈旧版本换 `=0u`（README 已注明）。
- 不加尾部复位：hermes 自己会恢复 focus / 粘贴 / 光标 / modifyOtherKeys。
- 包装只在 stdout 是 tty、且调用是 TUI 候选（`--tui` 或无参数）时发序列。
- 文档只讲症状与修法，不写试错经历；视频稿不需要。

## 边界

- 栈深 > 1 的旧版本（v0.18）不在覆盖范围，需换 `=0u`。
- tmux、ssh kitten 自持状态副本，未实测，遇到时用 `reset`。
- 异常退出（信号、崩溃）不在覆盖范围。
