# tui-mode-recovery

Automatically restore terminal mode state after TUI apps exit — fixes micro/vim/nano/less shortcuts broken by kitty CSI-u keyboard-protocol leakage.

> Symptom: after quitting a TUI (e.g. `hermes --tui`), opening micro in the same terminal and pressing Ctrl+Q inserts the literal text `113;5u`; arrows and Ctrl+C/X/O are dead too. Only a full `reset` used to recover.

## Root cause

`hermes --tui` (Ink TUI) pushes `CSI >1u` (kitty keyboard protocol, disambiguate mode) **while inside the alternate screen** when it detects kitty; from then on the terminal encodes Ctrl+Q as `CSI 113;5u` (113 = codepoint of `q`, 5 = Ctrl). Its `/quit` path never sends the matching pop `\e[<u` (upstream bug [hermes-agent#56759](https://github.com/NousResearch/hermes-agent/issues/56759); fix PRs [#57161](https://github.com/NousResearch/hermes-agent/pull/57161) / [#56765](https://github.com/NousResearch/hermes-agent/pull/56765) unmerged as of writing).

kitty keeps **separate CSI-u stacks for the main and the alternate screen** (spec-mandated, verifiable via `CSI ?u`), which explains the confusing behavior:

| Observation | Why |
|---|---|
| Shell prompt looks perfectly fine | main-screen stack is empty, flags = 0 |
| micro/vim/nano (alt-screen apps) type fragments | the alt screen they enter still has flags = 1 |
| `\e[<u` / `\e[=0u` sent from the main screen do nothing | they only touch the main stack |
| `reset` works | kitty's terminfo `rs1 = \E]\E\\\Ec` ends with RIS (`ESC c`), which resets BOTH screens |

Full measured matrix: [docs/probe-evidence.md](docs/probe-evidence.md).

## What this project provides

1. **Recovery sequence** (the core, usable standalone):

   ```sh
   printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'
   ```

   Enter the alt screen (`1049h`), pop + zero the flags there, return (`1049l`), pop + zero the main stack, then reset modifyOtherKeys (`>4m`), focus reporting (1004), bracketed paste (2004) and show the cursor. Excess pops are no-ops on an empty stack; `=0u` is stack-depth-independent; if the TUI died still inside the alt screen, the leading `1049h` is a no-op and the sequence still ends on the main screen.

2. **Shell wrappers** that auto-recover after the culprit exits:
   - fish: `functions/hermes.fish` (covers `hermes --tui` and bare `hermes`; autoloaded, no config.fish edit), `functions/tmr.fish` (generic)
   - bash / zsh: `lib/tui-recover.sh` (`tmr` + `hermes`)
3. **Probe** `tools/kbdprobe.py`: reports per-screen flags via `CSI ?u`, can reproduce the leak, can apply the fix
4. **Byte-level tests** `tests/test-byte-output.sh`: fake binary + real pty + `od`

## Install

```sh
./install.sh            # fish + bash + zsh (idempotent)
./install.sh --uninstall
```

## Usage

```sh
hermes --tui                     # auto-recover on exit (all shells)
tmr <command> [args...]          # generic wrapper
printf '\e[?1049h\e[<u\e[<u\e[<u\e[=0u\e[?1049l\e[<u\e[<u\e[<u\e[=0u\e[>4m\e[?1004l\e[?2004l\e[?25h'   # manual
```

Wrappers emit sequences only when stdout is a tty AND the invocation is a TUI candidate (`--tui`, or bare — covering `display.interface: tui`), so piped/scripted calls (`hermes chat -q`) stay clean; exit codes are preserved.

## Probe / tests

```sh
python3 tools/kbdprobe.py [--simulate] [--fix] [--json]
tests/test-byte-output.sh
```

`--simulate` deliberately dirties the alt-screen stack (that's the reproduction); pair it with `--fix`.

## Known limits

- tmux / kitty ssh kitten hold their own protocol state copy — `reset` remains the fallback there.
- Terminals without CSI-u support ignore the sequences (safe no-op).
- Once the upstream fix ships, `./install.sh --uninstall`.

## License

MIT
