# tui-mode-recovery

You finish with some TUI app, get your prompt back, and everything looks fine — then you open micro or vim or nano and the shortcuts are dead: Ctrl+Q does not quit, your buffer gets the literal text `113;5u` instead, and arrows and Ctrl+C stop working too. A full `reset` brings the terminal back, but nobody wants to do that after every TUI session.

This repo handles the whole thing: diagnose, clean, auto-recover. The broken state does not live in the app — it lives inside the terminal emulator, which is exactly why waiting for an app-side fix is not always enough.

## Quick start

```sh
# Already stuck? Recover right now (no screen clear, scrollback untouched)
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'

# Install auto-recovery: hermes --tui cleans up on exit
./install.sh

# Inspect: flags of the main and the alternate screen (0 = healthy)
python3 tools/kbdprobe.py
```

## What is going on

### The terminal is the key translator

The kitty keyboard protocol lets a program change how the terminal encodes keys: `CSI > 1 u` pushes a set of flags (e.g. disambiguate mode), `CSI < u` pops them back. Once disambiguation is on, Ctrl+Q — an ambiguous key — no longer sends the single byte DC1 but `CSI 113;5u`: 113 is the codepoint of `q`, 5 is Ctrl. Editors that do not speak CSI-u (micro, nano, many vim setups) treat the sequence as ordinary text and type it into the buffer.

### Somebody pushed, and never popped

When `hermes --tui` sees kitty it pushes `CSI > 1 u` **inside the alternate screen**. Not a guess: capture its startup bytes on a pty and `\e[?1049h` (enter alt) shows up at offset 787 while `\e[>1u` follows at 886 — screen switch first, push second. On exit that push is never popped: the unmount cleanup sends `1049l` (leave alt) *before* `\e[<u`, so the pop lands on the main stack; the `die()` / `dieWithCode()` path sends no pop at all. Either way the alt stack keeps flags = 1. Upstream issue [#56759](https://github.com/NousResearch/hermes-agent/issues/56759); both fix PRs are still unmerged.

### That is why the symptom looks weird

kitty keeps **separate protocol stacks for the main and the alternate screen**, with no inheritance — measured, not assumed; full data in [docs/evidence.md](docs/evidence.md):

| What you see | What is actually happening |
|---|---|
| prompt works fine | main-screen stack empty, flags = 0 |
| only micro / vim / nano break | they switch into alt, whose stack still has flags = 1 |
| `\e[<u` / `\e[=0u` at the prompt does nothing | it only touches the main stack |
| `reset` fixes everything | kitty's terminfo `rs1` ends with RIS (`ESC c`), which resets both screens |

## The cleanup sequence

```sh
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
```

| Fragment | What it does |
|---|---|
| `1049h`, then `<u`×3 with `=0u` | enter the alt screen, drain its stack and zero the flags |
| `1049l`, then `<u`×3 with `=0u` | back to the main screen, clear that stack too |
| `>4m` | reset modifyOtherKeys (some TUIs enable it as well) |
| `1004l`, `2004l`, `25h` | focus reporting and bracketed paste off, cursor visible |

Why it is safe: extra pops on an empty stack are no-ops by spec; `=0u` zeroes the flags regardless of stack depth; if the culprit died still inside the alt screen, the leading `1049h` is a no-op and the sequence still ends on the main screen.

## Components

| Path | Purpose |
|---|---|
| `functions/hermes.fish` | fish wrapper, autoloaded: cleans up after `hermes --tui` and bare `hermes` |
| `functions/tmr.fish`, `functions/tui-recover.fish` | generic `tmr <command>` wrapper, and a bare `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh: `tmr` and `hermes` functions |
| `tools/kbdprobe.py` | probe: per-screen `CSI ? u`, leak reproduction, fix, JSON output |
| `tests/test-byte-output.sh` | byte-level tests: fake binary on a real pty, exact bytes checked |
| `install.sh` | idempotent install, `--check` drift detection, uninstall |
| `bin/tui-recover` | standalone CLI: recover without any shell wrapper; `--dry-run` prints the bytes |
| `docs/evidence.md` | the measurements behind every claim |
| `.github/workflows/ci.yml` | CI: shellcheck, fish syntax, unit tests, byte-level and installer tests |

## Install and uninstall

```sh
./install.sh               # fish functions into ~/.config/fish/functions/,
                           # lib into ~/.local/share/tui-mode-recovery/lib/,
                           # marker-guarded, readable-guarded source block in bash/zsh rc
./install.sh --check       # verify installed copies match the repo; exit 1 on drift
./install.sh --uninstall   # removes only marked files and rc blocks; user-created functions untouched
```

Re-running is safe; after `git pull`, run it again to refresh the installed copies.

## Usage

```sh
hermes --tui               # auto-recover on exit (fish / bash / zsh)
tmr <command> [args…]      # any TUI that can dirty terminal state
tui-recover                # standalone CLI, same as the printf below (--dry-run shows bytes)
printf '...'               # manual recovery, same sequence as above
```

The wrappers emit sequences only when stdout is a tty and the invocation is a TUI candidate (`--tui`, or bare): piped/scripted calls (`hermes chat -q`) stay clean, exit codes are preserved.

## Diagnose and reproduce

```sh
python3 tools/kbdprobe.py                   # flags for both screens
python3 tools/kbdprobe.py --simulate        # dirty the alt stack on purpose, then report
python3 tools/kbdprobe.py --simulate --fix  # reproduce → clean → verify
python3 tools/kbdprobe.py --json            # machine-readable
```

`--simulate` is the reproduction: it really pushes inside the alt screen. Full matrix in [docs/evidence.md](docs/evidence.md).

## Tests

```sh
tests/test-byte-output.sh
```

12 byte-level cases (fish / bash / zsh wrappers, byte-exact on a real pty), 7 probe-parser unit tests, 11 installer cases (sandbox install, idempotency, drift detection, uninstall guards). CI runs the whole set on every push: shellcheck, fish syntax, Python unit tests, byte-level and installer tests. The fish cases load the repo's functions through a temporary `XDG_CONFIG_HOME`, so they test the repo, not an installed copy.

## Known limits

- tmux and ssh kitten keep their own protocol state; the targeted sequence may not be enough there — `reset` remains the fallback.
- Terminals without CSI-u support ignore these sequences; the wrappers are a harmless no-op for them.
- Once the upstream fix ships, remove this layer with `./install.sh --uninstall`.

## References

- Upstream issue: [#56759](https://github.com/NousResearch/hermes-agent/issues/56759) — TUI leaves terminal in corrupted state after clean /quit
- Fix PRs: [#57161](https://github.com/NousResearch/hermes-agent/pull/57161) (synchronous reset in die() / dieWithCode()), [#56765](https://github.com/NousResearch/hermes-agent/pull/56765) (`CSI = 0 u` after the stack pop)
- [kitty keyboard protocol spec](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## License

MIT
