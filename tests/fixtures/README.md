# Fixtures

Sample Steam metadata and a fake bottle, so that discovery can be tested
without a Steam install, a CrossOver install, an NVIDIA GPU, or this machine.

The reference machine has one Steam bottle, one library root and two games. The
layouts this tooling claims to support — several library roots, a library on a
second volume, an install directory whose name is not the game's, an executable
that is not where the last game's was — cannot be exercised against it. So the
parsing is written as pure functions over these files, kept apart from the
filesystem walking that feeds it, and the tests drive the parsing.

**Nothing here is a real binary.** The `.exe` files are short text files; their
sizes exist only so that ranking has something to tie-break on. The repository
ships no binaries, and these do not change that.

## The fake bottle — `bottle/`

A CrossOver prefix with **two drives, reached by relative symlinks** so the
expected answers are identical on every machine:

```
dosdevices/c:  -> ../drive_c        the bottle's own C:
dosdevices/d:  -> ../volume_d       a "second volume"
dosdevices/e:  -> ../volume_d       two letters, one target: C: breaks the tie
dosdevices/d:: -> /dev/rdisk9s1     a device node, which is not a drive
```

`cxbottle.conf` describes a bottle that has **never been set up** for NVK:
`CX_GRAPHICS_BACKEND` is set and there is no managed block. That is the state a
new user is in, and it is what `nvk-doctor` has to recognise.

### Two Steam library roots

`drive_c/Program Files (x86)/Steam` and `volume_d/SteamLibrary`, with
`libraryfolders.vdf` listing both. A tool that reads only one `common/`
directory finds half the games; one that assumes `C:` builds a launcher
pointing at a path that does not exist.

### The games, and what each one is for

| appid | Name | installdir | Tests |
|---|---|---|---|
| 730 | Counter-Strike 2 | `Counter-Strike Global Offensive` | the folder is not the name |
| 228980 | Steamworks Common Redistributables | `Steamworks Shared` | Steam's plumbing is not a game |
| 1422450 | Deadlock | `Deadlock` | a game on the second volume |
| 999001 | `Tom's "Game" (2024) & $(id) …` | `Toms Game` | quoting, everywhere |

Appid 999001's name holds a single quote, double quotes, a backslash, a
percent sign, angle brackets, a command substitution and a backtick. It exists
so that every place a name is interpolated — a generated shell script, an
`Info.plist`, an AppleScript dialog, a filename — is proven not to execute it.
`expected-999001-name.txt` holds the name as it should come back out.

### The executable layouts

* **Source 2** (`game/bin/win64/`) — Deadlock, Counter-Strike 2
* **Unreal** (`Binaries/Win64/`, with `Engine/Binaries/Win64/`) — Toms Game
* **Top level** — Toms Game also ships `TomsGame.exe` beside its launcher

Each game ships decoys that ranking must handle: a launcher that is *larger*
than the real binary, a crash handler, an editor, bundled redistributables, and
an `EasyAntiCheat/` directory for the anticheat check.

## The other fixtures

| Path | Purpose |
|---|---|
| `bottle-configured/` | a prefix that *has* been set up, whose `cxbottle.conf` carries the duplicate-key damage seen on the reference machine |
| `cxbottle-duplicates.conf` | the same file, standalone, for `nvk-bottle clean-conf` |
| `fake-runtime/` | stands in for the NVK runtime, so `nvk-mkapp` will run |
| `fake-crossover/` | stands in for CrossOver.app, for the same reason |

## Adding to these

Add a fixture whenever a real layout breaks something, and a test that fails
without the fix. A bug that only reproduces on someone else's machine is worth
a fixture precisely because it cannot be reproduced here.
