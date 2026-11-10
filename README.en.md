# tui-mode-recovery

After a TUI app exits, the terminal can keep a stale keyboard-protocol state: the shell prompt looks perfectly normal, yet in micro / vim / nano pressing Ctrl+Q inserts the literal text `113;5u` and arrows, Ctrl+C/X are dead too — only a full `reset` brings the terminal back.

This repo fixes the **root cause** instead of repackaging `reset`: what leaks is the kitty keyboard-protocol stack, and **kitty keeps one stack per screen (main and alternate)**. The culprit pushed its flags *inside the alternate screen*, so any cleanup that only touches the current (main) screen provably cannot reach it.

## Quick start

```sh
# 1) Terminal already stuck? Recover now (no screen clear, no scrollback loss)
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'

# 2) Permanent fix: install the auto-recovery wrappers (fish / bash / zsh, idempotent)
./install.sh

# 3) Diagnose: query the flags of the main and the alternate screen separately
python3 tools/kbdprobe.py
```

## Root cause

### The protocol, in one paragraph

The kitty keyboard protocol lets a program **push** a set of key-encoding flags (`CSI > 1 u`, e.g. disambiguate mode) onto a per-screen stack, and **pop** them with `CSI < u`. With disambiguation on, Ctrl+Q has no legacy single-byte encoding (DC1 / 0x11 would be ambiguous), so the terminal encodes it as `CSI 113;5u` — 113 is the codepoint of `q`, 5 is the Ctrl modifier. Programs that don't understand CSI-u (micro, nano, stock vim setups) insert that sequence as literal text.

### The culprit: a push that never gets popped

`hermes --tui` (Ink TUI) detects kitty in its extended-keys allowlist and pushes `CSI > 1 u` **while inside the alternate screen**. Its `/quit` path (`die()` / `dieWithCode()`) never sends the matching pop — upstream issue [hermes-agent#56759](https://github.com/NousResearch/hermes-agent/issues/56759); fix PRs [#57161](https://github.com/NousResearch/hermes-agent/pull/57161) and [#56765](https://github.com/NousResearch/hermes-agent/pull/56765) were still unmerged when this was written.

### Why only editors break while the prompt stays fine

kitty maintains **separate protocol stacks for the main and the alternate screen** (spec-mandated; measured, see [docs/probe-evidence.md](docs/probe-evidence.md)). The push lands on the alt stack, so:

| What you see | What actually happens |
|---|---|
| shell prompt works normally | the main-screen stack is empty, flags = 0 |
| micro / vim / nano type fragments on every shortcut | the alt screen they switch into still carries flags = 1 |
| sending `\e[<u` / `\e[=0u` at the prompt does nothing | it touches the main stack only |
| `reset` always fixes it | kitty's terminfo `rs1` ends with RIS (`ESC c`), which resets both screens |

## The cleanup sequence

```sh
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
```

| Fragment | Purpose |
|---|---|
| `1049h` → `<u`×3 + `=0u` | enter the alt screen, drain and zero its stack |
| `1049l` → `<u`×3 + `=0u` | back to the main screen, clear it as well |
| `>4m` | reset modifyOtherKeys (some TUIs enable it too) |
| `1004l` / `2004l` / `25h` | focus reporting and bracketed paste off, cursor visible |

Why it is safe:

- Extra pops on an empty stack are no-ops by spec; `=0u` zeroes the flags regardless of stack depth, so any leftover depth is cleared.
- If the culprit died still inside the alt screen, the leading `1049h` is a no-op and the sequence still ends on the main screen.

## What is in the repo

| Path | Purpose |
|---|---|
| `functions/hermes.fish` | fish wrapper: autoloaded; recovers after `hermes --tui` and bare `hermes` (covers `display.interface: tui`) |
| `functions/tmr.fish` / `tui-recover.fish` | generic `tmr <command>` wrapper, and a bare `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh: `tmr` and `hermes` functions |
| `tools/kbdprobe.py` | probe: per-screen `CSI ? u` flags, leak reproduction, fix, JSON output |
| `tests/test-byte-output.sh` | byte-level tests: fake binary + real pty; exact bytes, exit codes, piped silence |
| `install.sh` | idempotent install / uninstall |
| `docs/probe-evidence.md` | raw probe measurements and interpretation |

## Install / uninstall

```sh
./install.sh               # fish: copies functions into ~/.config/fish/functions/
                           # bash/zsh: appends a marker-guarded source block to existing rc files
./install.sh --uninstall   # removes only files and rc blocks carrying this project's marker
```

Idempotent; start a new shell afterwards. Uninstall is guarded: same-named fish functions not installed by this project are left alone.

## Usage

```sh
hermes --tui               # automatic: recovery runs on exit (fish / bash / zsh)
tmr <command> [args...]    # generic: any TUI that can dirty terminal state
printf '...'               # manual: run the cleanup sequence in a stuck terminal
```

The wrappers emit sequences only when **stdout is a tty** and the invocation is a TUI candidate (`--tui`, or bare) — piped/scripted calls (`hermes chat -q`) stay clean and exit codes are preserved.

## Probe

```sh
python3 tools/kbdprobe.py                   # flags for main + alternate screen
python3 tools/kbdprobe.py --simulate        # recreate the leak in the alt stack, then report
python3 tools/kbdprobe.py --simulate --fix  # reproduce → repair → verify
python3 tools/kbdprobe.py --json            # machine-readable
```

The probe sends `CSI ? u` and parses the `CSI ? flags u` reply; `1049h` / `1049l` switch screens so each stack can be queried. `--simulate` really dirties the alt stack (that IS the reproduction) — pair it with `--fix`.

## Tests

```sh
tests/test-byte-output.sh
```

12 cases: exact two-screen byte sequence, exit-code preservation, piped silence, non-TUI args silence, bare-`hermes` trigger, and all three wrappers (fish / bash / zsh). The fish cases use a temporary `XDG_CONFIG_HOME`, so they exercise the repo's functions rather than whatever is installed.

## Known limits

- tmux and kitty's ssh kitten keep their own copy of protocol state; the targeted sequence may not be enough there — `reset` remains the fallback.
- Terminals without CSI-u support ignore these sequences; the wrappers are a harmless no-op for them.
- Once the upstream fix ships (expected with hermes-agent v0.24.0), remove everything with `./install.sh --uninstall`.

## References

- Upstream bug: [hermes-agent#56759](https://github.com/NousResearch/hermes-agent/issues/56759) — TUI leaves terminal in corrupted state after clean /quit
- Fix PRs: [#57161](https://github.com/NousResearch/hermes-agent/pull/57161) (synchronous reset in die()/dieWithCode()), [#56765](https://github.com/NousResearch/hermes-agent/pull/56765) (`CSI = 0 u` after the stack pop)
- [kitty keyboard protocol spec](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## License

MIT
