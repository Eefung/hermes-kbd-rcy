# TUI Terminal Mode Recovery

You finish with a TUI app, get your prompt back, and everything looks fine. Then you open micro, vim or nano and every Ctrl shortcut is dead: Ctrl+Q does not quit, your buffer gets the literal text `113;5u` instead, and save/find shortcuts fail the same way (arrows and plain typing are unaffected).

This repo gives you one command that does not clear the screen, plus a small tool that makes it automatic after one install.

## How it works

`hermes --tui` leaves a keyboard setting behind when it exits (upstream [#56759](https://github.com/NousResearch/hermes-agent/issues/56759), still unfixed). The probe prints two lines:

```
main             0    OK (legacy key encoding)
alt              1    STUCK — alt-screen apps (vi/micro/nano) will see CSI-u fragments like "113;5u"
```

The command-line screen (main) reads 0; the fullscreen-program screen (alt) reads 1. An editor switches into the alt screen, inherits that setting, and keys become text.

hermes restores focus reporting, bracketed paste, modifyOtherKeys and the cursor itself on exit (measured: its final reset block ends `1004l → 2004l → 1049l → <u → >4m → 0m → 25h`). The one thing it does not restore is the alt screen's keyboard setting, because `<u` comes after `1049l`, so the pop lands on the main screen. The command therefore does exactly one thing: enter the alt screen, pop, come back.

Popping is the same mechanism hermes uses in its own exit cleanup. On v0.23.0 the stack holds exactly one entry at exit (measured), so a single `<u>` restores the alt screen. Full measurements: [evidence](docs/evidence.md).

## Installation

```sh
./install.sh               # safe to re-run; refresh after git pull
./install.sh --check       # verify installed copies match the repo
./install.sh --uninstall   # removes only marked files and rc blocks
```

## Usage

```sh
printf '\e[?1049h\e[<u\e[?1049l'   # already stuck? recover now (no screen clear, scrollback untouched)
hermes --tui                       # auto-recover on exit once installed (fish / bash / zsh)
tmr <command> [args…]              # any TUI that can dirty terminal state
tui-recover                        # standalone CLI, same as the printf above
python3 tools/kbdprobe.py          # check: read both screens, 0 means healthy
python3 tools/kbdprobe.py --simulate --fix   # reproduce → clean → verify
python3 tools/kbdprobe.py --json   # machine-readable
```

Wrappers emit sequences only when stdout is a tty and the invocation is a TUI candidate (`--tui`, or bare): piped/scripted output stays clean and exit codes are preserved.

## FAQ

### Does it help under tmux or ssh kitten?

Not always. Those layers keep their own copy of the state, so the targeted cleanup may not be enough; `reset` remains the fallback — a full reset covering both screens, at the cost of clearing the screen.

### Why not fix old hermes (v0.18) too?

v0.18 accumulates pushes, so a single `<u>` is not enough and those builds are out of scope. `=0u` is no substitute either: it only rewrites the flags, the stack entry stays and the next `<u>` brings it right back (see [evidence](docs/evidence.md)).

### What about terminals without CSI-u support?

They ignore these sequences, so the wrappers are a harmless no-op there.

### Does it clean up after a signal or crash?

No. The wrappers emit the sequence on the normal exit path only.

### Do I still need this after the upstream fix ships?

No — remove the layer with `./install.sh --uninstall`.

## Development

```sh
tests/test-byte-output.sh                              # 12 byte-level cases
tests/test-install.sh                                  # 11 installer cases
python3 -m unittest discover -s tests -p 'test_*.py'   # 7 probe-parser unit tests
```

CI runs everything on every push, including shellcheck and fish syntax checks.

## Documentation

| Path | Purpose |
|---|---|
| `functions/hermes.fish` | fish wrapper, autoloaded: cleans up after `hermes --tui` and bare `hermes` |
| `functions/tmr.fish`, `functions/tui-recover.fish` | generic `tmr <command>` wrapper, and a bare `tui-recover` |
| `lib/tui-recover.sh` | bash / zsh: `tmr` and `hermes` functions |
| `tools/kbdprobe.py` | probe: reads `CSI ? u` per screen, reproduce / fix / JSON |
| `bin/tui-recover` | standalone CLI: no shell wrapper needed, `--dry-run` shows bytes |
| `install.sh` | install, `--check` drift detection, uninstall |
| `tests/` | byte-level cases, installer cases, probe-parser unit tests |
| `.github/workflows/ci.yml` | runs all three suites on every push, plus shellcheck and fish syntax checks |
| `docs/evidence.md` | measurements: which screen the push lands on, whether the two screens share a stack, stack depth, what `=0u` actually does |

## References

- Upstream issue: [#56759](https://github.com/NousResearch/hermes-agent/issues/56759) — TUI leaves terminal in corrupted state after clean /quit
- Fix PRs: [#57161](https://github.com/NousResearch/hermes-agent/pull/57161), [#56765](https://github.com/NousResearch/hermes-agent/pull/56765) (both unmerged)
- [kitty keyboard protocol spec](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)

## License

MIT, see [`LICENSE`](LICENSE).
