# tui-mode-recovery

TUI 应用退出后自动恢复终端模式状态:修复 kitty CSI-u 键盘协议残留导致的 micro/vim/nano/less 快捷键失效。

> 症状:退出某个 TUI(如 `hermes --tui`)后,在同一终端里打开 micro,按 Ctrl+Q 却被当作文本输入了 `113;5u`;方向键、Ctrl+C/X/O 等同样失灵。只有手动执行 `reset` 才能恢复。

## 为什么会坏

`hermes --tui`(Ink TUI)检测到 kitty 在它的扩展键白名单里,会在 **alt screen 里**发送 `CSI >1u`,推入 kitty keyboard protocol 的 disambiguate 模式栈;此后 kitty 把 Ctrl+Q 编码为 `CSI 113;5u`(113 = 字母 q 的码点,5 = Ctrl 修饰符)。而它的 `/quit` 退出路径不会发回对应的弹出序列 `\e[<u`——上游 bug 见 [hermes-agent#56759](https://github.com/NousResearch/hermes-agent/issues/56759),修复 PR [#57161](https://github.com/NousResearch/hermes-agent/pull/57161)、[#56765](https://github.com/NousResearch/hermes-agent/pull/56765) 截至写作时未合并。

kitty 对 **主屏和 alt screen 各维护一份独立的协议栈**(规范如此,可用 `CSI ?u` 查询实测),这带来几个反直觉的后果:

| 现象 | 原因 |
|---|---|
| shell 提示符看起来一切正常 | 主屏栈是空的,flags = 0 |
| micro/vim/nano(走 alt 屏)按键全部变文本 | 它们进入的 alt 屏残留 flags = 1 |
| 从主屏发 `\e[<u` / `\e[=0u` 清理**无效** | 只作用于主屏栈,碰不到 alt 栈 |
| `reset` 有效 | kitty 的 terminfo `rs1 = \E]\E\\\Ec`,末尾的 RIS(`ESC c`)复位**两屏**的全部状态 |

本仓库用探针实测的完整矩阵见 [docs/probe-evidence.md](docs/probe-evidence.md)。

## 这个项目做什么

1. **恢复序列**(核心,一条命令,可单独手动使用):

   ```sh
   printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
   ```

   先进 alt 屏(`1049h`)弹栈并清零 flags,回主屏(`1049l`)再清一遍,然后复位 modifyOtherKeys(`>4m`)、focus reporting(1004)、bracketed paste(2004),并显示光标。多余的 pop 对空栈是无害 no-op,`=0u` 清零与栈深度无关,所以对任意深度的残留都有效;若 TUI 死在 alt 屏里没出来,开头的 `1049h` 是 no-op,序列结束时仍保证回到主屏。

2. **shell 包装函数**,让肇事命令退出后自动恢复:
   - fish:`functions/hermes.fish`(针对 `hermes --tui`,自动加载,无需改 config.fish)、`functions/tmr.fish`(通用版)
   - bash / zsh:`lib/tui-recover.sh`(提供 `tmr` 与 `hermes` 两个函数)
3. **探针** `tools/kbdprobe.py`:用 `CSI ?u` 查询各屏 flags,可复现残留、可执行修复
4. **字节级测试** `tests/test-byte-output.sh`:fake binary + pty + `od`,验证包装函数实际发出的字节、退出码是否保留、管道场景是否静默

## 安装

```sh
./install.sh            # fish + bash + zsh 全部安装(幂等,重复执行安全)
./install.sh --uninstall
```

- fish:复制 `functions/*.fish` 到 `~/.config/fish/functions/`,新 shell 自动生效
- bash/zsh:向 `~/.bashrc` / `~/.zshrc` 追加带标记(`# >>> tui-mode-recovery >>>`)的 `source` 块,不改动其余内容

## 使用

```sh
# 自动:hermes --tui 退出后立即恢复(fish/bash/zsh 均生效)
hermes --tui

# 通用包装:任何会污染终端状态的 TUI 命令
tmr <command> [args...]

# 手动:在已卡住的终端里直接执行恢复序列
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
```

包装函数只在「stdout 是 tty 且参数匹配」时发序列:`hermes chat -q`、`tmr` 在管道/脚本里调用时输出不受污染;退出码原样保留。

## 探针

```sh
python3 tools/kbdprobe.py                # 报告主屏 / alt 屏 flags
python3 tools/kbdprobe.py --simulate     # 先在 alt 屏复现残留(故意弄脏),再报告
python3 tools/kbdprobe.py --simulate --fix   # 复现 → 修复 → 复查
python3 tools/kbdprobe.py --json
```

注意:`--simulate` 会真的把 alt 屏栈弄脏(这正是复现手段),请配合 `--fix` 或手动恢复序列使用。

## 测试

```sh
tests/test-byte-output.sh
```

## 已知边界

- tmux、kitty 的 ssh kitten 这类自己维护一份协议状态的中间层,可能需要 `reset` 兜底
- 不支持 CSI-u 的终端会忽略这些序列,包装函数对它们是安全 no-op
- 上游合并修复后(预计随 v0.24.0 发布),`./install.sh --uninstall` 一键移除

## 参考

- 上游 bug:[hermes-agent#56759](https://github.com/NousResearch/hermes-agent/issues/56759) —— TUI leaves terminal in corrupted state after clean /quit
- 修复 PR:[#57161](https://github.com/NousResearch/hermes-agent/pull/57161)(die()/dieWithCode() 补同步 reset)、[#56765](https://github.com/NousResearch/hermes-agent/pull/56765)(kitty 栈 pop 后追加 CSI = 0 u)
- [kitty keyboard protocol 文档](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## License

MIT
