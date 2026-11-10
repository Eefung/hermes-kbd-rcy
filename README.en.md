# tui-mode-recovery

You finish with a TUI app, get your prompt back, and everything looks fine. Then you open micro, vim or nano and every Ctrl shortcut is dead: Ctrl+Q does not quit, your buffer gets the literal text `113;5u` instead, and save/find shortcuts fail the same way (arrows and plain typing are unaffected). `reset` brings the terminal back, at the price of wiping the screen.

This repo gives you one command that does not clear the screen, plus a small tool that makes it automatic after one install.

## Quick start

```sh
# Already stuck? Recover now (no screen clear, scrollback untouched)
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'

# Install once: hermes --tui cleans up on exit (fish / bash / zsh)
./install.sh

# Check: read both screens, 0 means healthy
python3 tools/kbdprobe.py
```

## Why the command works

`hermes --tui` leaves a keyboard setting behind when it exits (upstream [#56759](https://github.com/NousResearch/hermes-agent/issues/56759), still unfixed). The probe prints two lines:

```
main             0    OK (legacy key encoding)
alt              1    STUCK — alt-screen apps (vi/micro/nano) will see CSI-u fragments like "113;5u"
```

The command-line screen (main) reads 0; the fullscreen-program screen (alt) reads 1. An editor switches into the alt screen, inherits that setting, and keys become text. Each screen keeps its own copy, so the cleanup has to go in, clear, and come back to clear again. That is exactly what the one-liner does.

hermes restores focus reporting, bracketed paste, modifyOtherKeys and the cursor itself on exit (measured: its final reset block ends `1004l → 2004l → 1049l → <u → >4m → 0m → 25h`). The one thing it does not restore is the alt screen's keyboard setting, because `<u` comes after `1049l`, so the pop lands on the main screen. The tail of our command (`>4m`, `1004l`, `2004l`, `25h`) is a no-op on a normal exit; it only matters when the app dies abnormally (signal, crash).

Extra pops on an empty stack are harmless, and `=0u` zeroes the setting regardless of stack depth. Full measurements: [docs/evidence.md](docs/evidence.md).

## Components

| Path | Purpose |
|---|---|
| `functions/hermes.fish` | fish wrapper, autoloaded: cleans up after `hermes --tui` and bare `hermes` |
| `functions/tmr.fish`, `functions/tui-recover.fish` | generic `tmr <command>` wrapper, and a bare `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh: `tmr` and `hermes` functions |
| `tools/kbdprobe.py` | probe: reads `CSI ? u` per screen, reproduce / fix / JSON |
| `bin/tui-recover` | standalone CLI: no shell wrapper needed, `--dry-run` shows bytes |
| `install.sh` | install, `--check` drift detection, uninstall |
| `tests/`, `.github/workflows/ci.yml` | byte-level tests, installer tests, probe unit tests; CI runs all of it |

## Install and uninstall

```sh
./install.sh               # safe to re-run; refresh after git pull
./install.sh --check       # verify installed copies match the repo
./install.sh --uninstall   # removes only marked files and rc blocks
```

## Usage

```sh
hermes --tui               # auto-recover on exit (fish / bash / zsh)
tmr <command> [args…]      # any TUI that can dirty terminal state
tui-recover                # standalone CLI, same as the printf above
```

Wrappers emit sequences only when stdout is a tty and the invocation is a TUI candidate (`--tui`, or bare): piped/scripted output stays clean and exit codes are preserved.

## Diagnose

```sh
python3 tools/kbdprobe.py                   # read both screens
python3 tools/kbdprobe.py --simulate --fix  # reproduce → clean → verify
python3 tools/kbdprobe.py --json            # machine-readable
```

## Tests

```sh
tests/test-byte-output.sh                              # 12 byte-level cases
tests/test-install.sh                                  # 11 installer cases
python3 -m unittest discover -s tests -p 'test_*.py'   # 7 probe-parser unit tests
```

CI runs everything on every push, including shellcheck and fish syntax checks.

## Known limits

- tmux and ssh kitten keep their own copy of the state; the targeted cleanup may not be enough there, so `reset` remains the fallback (full reset, both screens, at the cost of the screen).
- Terminals without CSI-u support ignore these sequences; the wrappers are a harmless no-op for them.
- Once the upstream fix ships, remove this layer with `./install.sh --uninstall`.

## References

- Upstream issue: [#56759](https://github.com/NousResearch/hermes-agent/issues/56759) — TUI leaves terminal in corrupted state after clean /quit
- Fix PRs: [#57161](https://github.com/NousResearch/hermes-agent/pull/57161), [#56765](https://github.com/NousResearch/hermes-agent/pull/56765) (both unmerged)
- [kitty keyboard protocol spec](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## License

MIT
