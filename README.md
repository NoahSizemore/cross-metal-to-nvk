# cross-metal-to-nvk

Run Windows games in CrossOver on an **Intel Hackintosh** through the **nativeNVK** NVIDIA path, instead of CrossOver's default Metal translation.

These are configuration scripts. They ship **no binaries** and redistribute
nothing — you install NullMoth's NVIDIA driver and its Wine/NVK runtime
yourself, and these tools point CrossOver at it.

> **Status: experimental.** Built and verified on a single machine (RTX 4070,
> macOS 26 Tahoe, CrossOver 26.3). The runtime's author does not qualify
> commercial CrossOver. Treat performance numbers below as one data point, not
> a promise.

---

## What this is not

* **Not a driver.** You install NullMoth's driver *including its Wine
  runtime*. This repo contains shell scripts and documentation only.
* **Not for Apple Silicon.** Use D3DMetal / Game Porting Toolkit there. This
  path requires a real NVIDIA GPU on an Intel machine.
* **Not a performance promise.** It is slower than the same card on Windows.
  See [Performance](#performance) for the measured gap and its known causes.
* **Not an anticheat workaround.** Games with kernel-level anticheat (EAC,
  BattlEye, Vanguard) do not run under Wine on macOS, and nothing here changes
  that.

---

## How it works

The point of this project is to get D3D11 calls to native NVK rather than
through Metal. The working chain is:

```
Game (D3D11)
  └─> DXVK 3.1.1+nvk           the runtime's repaired pair, installed into system32
       └─> Wine's Vulkan bridge  libnvk_wine.dylib, selected by DYLD_LIBRARY_PATH
            └─> native NVK        Mesa, reporting Vulkan 1.4.x
                 └─> NVIDIA open kernel modules ─> your GPU
```

Explicitly **not** in use: D3DMetal, DXMT, MoltenVK, the NVMTL AIR translator,
or wined3d.

### Why generated `.app` launchers, and not a patch to CrossOver

Two reasons, both learned the hard way:

1. **macOS strips `DYLD_*` across hardened-runtime exec boundaries.** The
   variable that selects the NVK frontend therefore cannot be inherited down
   through Steam's helper chain. It has to be set in the process that *becomes*
   the game. A generated launcher is that process.
2. **CrossOver regenerates its own launchers.** Edits made there do not survive
   an update.

A bundle built on your own machine carries no quarantine attribute, so there is
no Gatekeeper prompt.

### Three environment lessons

GUI-launched apps get a far smaller environment than your interactive shell.
Everything your shell quietly supplies becomes someone else's bug report.

| Variable | Why it needs explicit handling |
|---|---|
| `DYLD_LIBRARY_PATH` | Selects the NVK frontend. Stripped across exec; must be set per-process, never globally. |
| `WINEDLLOVERRIDES`, `DXVK_*` | Windows-side vars do not reach the game from the calling shell. CrossOver builds the Wine environment from `cxbottle.conf [EnvironmentVariables]`. |
| `CX_BOTTLE_PATH` | CrossOver's `--bottle NAME` only searches its two default bottle directories. A bottle on another volume fails from a GUI app with "Unable to find the bottle". |

**Do not set `CX_GRAPHICS_BACKEND`.** Setting it to `wine` routes D3D through
wined3d-on-OpenGL; macOS OpenGL caps at 4.1, which cannot do Shader Model 5.
The symptom is `Failed to create DirectX 11 render device!`.

---

## Requirements

* Intel Mac or Hackintosh (x86_64)
* macOS 15 or newer — the runtime is built against the macOS 15 SDK
* NVIDIA Turing or newer (RTX 20 / GTX 16 and later)
* NullMoth's driver **including the Wine runtime** at
  `/Library/GPUBundles/nvmtl/wine`
* CrossOver (verified against 26.3)

There is deliberately no version number for the driver here. Its bundle and its
runtime report different identifiers, and they have already disagreed with each
other on the reference machine — so check the capability, not the label:

```sh
/Library/GPUBundles/nvmtl/wine/bin/nvk-runtime check /Library/GPUBundles/nvmtl/wine
```

You want `"result" : "PASS"`. `nvk-doctor` runs this for you and prints both
identifiers side by side.

---

## Quick start

```sh
git clone <this repo> && cd cross-metal-to-nvk
./bin/nvk-setup
```

`nvk-setup` runs the whole arc and asks before each step that changes
anything: check the machine, configure the bottle, find the game, pick its
executable, warn about anticheat, write a profile, generate the launchers.

Every question it asks is also a flag, so a working setup reproduces as one
line — which is what a bug report should contain:

```sh
./bin/nvk-setup --bottle Steam --game Deadlock --args '-dx11' --yes
```

### Or do it by hand

```sh
# 1. Check the machine. Read-only; changes nothing, and never needs sudo.
#    Exit status is the gate: 0 ready, 2 usable with caveats, 1 do not continue.
./bin/nvk-doctor                    # host, GPU, driver, runtime, Vulkan, CrossOver
./bin/nvk-doctor --bottle Steam     # ...and one bottle's DXVK and configuration

# 2. Configure a bottle. Installs the runtime's DXVK into the prefix and
#    writes the Wine environment block into cxbottle.conf, backing it up first.
#    It asks before touching the file, and needs the bottle's apps closed.
./bin/nvk-bottle setup Steam

# 3. Find the game and its executable. Output is tab-separated.
./bin/nvk-steam games Steam
./bin/nvk-steam exes "/path/from/the/previous/command"
./bin/nvk-winepath to-win Steam "/path/to/the/chosen.exe"

# 4. Generate launchers. The two-app split is the documented default:
#    one app to start Steam under NVK, one for the game itself.
./bin/nvk-mkapp --bottle Steam \
  --app 'C:\Program Files (x86)\Steam\steam.exe' --name 'Steam (NVK)'

./bin/nvk-mkapp --bottle Steam \
  --app 'C:\...\game\bin\win64\yourgame.exe' \
  --name 'Your Game (NVK)' --args '-dx11' \
  --save-profile profiles/your-game-123456.conf
```

Launchers land in `~/Applications` and log to `~/Library/Logs/nvk-<name>.log`.

**Undo everything:** `./bin/nvk-bottle undo Steam`

### Optional flags

* `nvk-bottle setup <bottle> --d3d12` also installs vkd3d, for D3D12 titles.
* `nvk-bottle setup <bottle> --dyld` additionally writes `DYLD_LIBRARY_PATH`
  into `cxbottle.conf`, which lets you launch from CrossOver's GUI or Steam's
  Play button with no generated app. The runtime's README advises against
  setting it globally; per-bottle is narrower, but if the bottle misbehaves,
  re-run `setup` without it.
* `nvk-mkapp --needs-steam` starts Steam first and waits for it. This is a
  convenience that may not work everywhere — prefer the two-app split.
* `nvk-mkapp --icon-from '/path/to/some.app'` borrows an icon.
* `nvk-mkapp --regenerate-all` rebuilds every launcher from `profiles/`. Run it
  after a runtime or CrossOver update, since generated launchers pin their
  paths (design rule 6) and therefore go stale.
* `nvk-setup --dry-run` shows the whole plan and writes nothing.

---

## Verifying it worked

Check the DXVK log in `<bottle>/drive_c/dxvk/`. You want:

```
info:  Binding model: Legacy
info:  Found device: NVIDIA GeForce RTX 4070 (NVK AD104-A) (NVK 26.3.1)
info:  D3D11InternalCreateDevice: Using feature level D3D_FEATURE_LEVEL_11_1
```

An **AMD vendor ID** (`0x1002` / `0x73df`) reported in DXGI is **normal**. That
is DXVK's NVAPI workaround, not evidence of the wrong GPU:

```
info:  DXGI: Hiding actual GPU, reporting:
info:    vendor ID: 0x1002
```

To confirm NVK itself is live, independent of Wine:

```sh
VK_DRIVER_FILES=/Library/GPUBundles/nvmtl/nvk_icd.json ./bin/vk-icd-probe.py
```

A `vendorID` of `0x10de` with your card's name means native NVK is working.
Do not run this under `sudo` — the Vulkan loader ignores `VK_DRIVER_FILES` for
elevated processes.

---

## Performance

One measured data point: **Deadlock**, RTX 4070, low settings, FSR2 2x —
**35–130 fps**, 20,299 frames in a single session. Playable, and well short of
the same card on Windows.

Three known causes, in rough order of cost:

1. **Framebuffer compression is refused on every render target.** The driver
   logs `unsupported pte_kind` and falls back uncompressed. Likely the single
   biggest fixable item.
2. **One full-frame GPU copy per present.** Measured at exactly
   2560×1440×4 bytes per frame; presentation is not zero-copy. Lowering
   resolution attacks this directly.
3. **DXVK's own D3D11→Vulkan overhead.**

See [docs/DRIVER-ISSUES.md](docs/DRIVER-ISSUES.md) for the full write-ups,
including two driver bugs that cause silent visual corruption.

---

## Documentation

| Document | Contents |
|---|---|
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptoms, causes, fixes |
| [docs/DRIVER-ISSUES.md](docs/DRIVER-ISSUES.md) | Upstream driver findings with reproduction detail |
| [docs/upstream/](docs/upstream/) | The same three findings, written as reports ready to submit |
| [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) | Per-game notes, anticheat, Steam launch caveats |
| [profiles/README.md](profiles/README.md) | The profile format |
| [tests/fixtures/README.md](tests/fixtures/README.md) | What the fixtures stand in for |

---

## Tests

```sh
./tests/run.sh
```

No GPU, no CrossOver and no Steam required: the suite runs against fixtures in
`tests/fixtures/`, which provide a bottle with two drives, two Steam library
roots, a game whose folder is not its name, a game on a second volume, and a
game whose name is a quoting attack. Stand-ins for CrossOver and the runtime
let launcher generation be tested on a machine that has neither, and further
fixtures cover a bottle directory containing a space, a manifest with Windows
line endings, and bottles in both configured and unconfigured states.

That split is deliberate. The reference machine has one GPU, one Steam bottle
and two games, so the layouts this tooling claims to handle cannot be tested
against it. Parsing is written as pure functions over files, and the tests
drive those. Anything that genuinely needs *this* hardware is `nvk-doctor`'s
job, not the suite's.

---

## Repository layout

```
bin/
  nvk-setup         the guided front door; drives everything below  (zsh)
  nvk-doctor        preflight gate and bug-report dump (read-only)
  nvk-bottle        dirs / list / path / setup / run / status / undo,
                    plus install-dlss / restore-dlss and clean-conf
  nvk-steam         root / libraries / games / exes / anticheat, plus the
                    parsers (kv, parse-acf, parse-libraryfolders) on their own
  nvk-winepath      drives / to-win / from-win, via the bottle's dosdevices
  nvk-profile       list / path / read / write / validate / name
  nvk-mkapp         generates .app launchers from a profile or from flags
  vk-icd-probe.py   enumerates the NVK ICD via ctypes; no Vulkan SDK needed
profiles/           per-game profiles: the output of record (yours are
                    gitignored; they record your own paths)
tests/              the suite, and fixtures that stand in for other machines
docs/               shipping documentation
```

`nvk-setup` is the only `zsh` script, because building menus in POSIX `sh`
without arrays is miserable and `zsh` is guaranteed present on macOS. It calls
the others **as subprocesses**, reading their tab-separated output; nothing is
sourced across the `zsh`/`sh` boundary, where word-splitting rules differ.
Everything else is `#!/bin/sh`.

Each tool is usable on its own, which is the point: the wizard is a driver, not
a fourth implementation of anything.

```sh
nvk-steam games Steam                    # appid, name, installdir, path, present
nvk-steam exes "<game dir>"              # score, size, path  (best first)
nvk-winepath to-win Steam "<unix path>"  # the Windows path, via dosdevices
nvk-profile  validate profiles/*.conf
```

---

## Design rules

These are constraints, not preferences. Changes that violate them are bugs.

1. **Never redistribute the runtime.** It is PolyForm Noncommercial and bundles
   NVIDIA's NGX license. Scripts only; verify the user's copy with
   `nvk-runtime check`.
2. **Never require sudo.** Nothing here needs it. The tools that change
   something — `nvk-setup`, `nvk-bottle`, `nvk-mkapp` — refuse to run as root.
   `nvk-doctor` only warns, because refusing to produce a diagnostic report
   helps nobody, and the read-only query tools do not check at all.
3. **Reversible by construction.** Back up `cxbottle.conf` before editing it,
   mark additions with a sentinel so re-runs replace rather than duplicate, and
   keep `undo` a first-class command.
4. **Scope `DYLD_*` to one process, never globally.**
5. **Generated launchers log by default and raise a dialog on failure.** A GUI
   app whose output goes to `/dev/null` is undebuggable.
6. **Pin every path at generation time.** Ambient configuration is the enemy.
7. **Read versions, never assert them.** Runtime builds change underneath the
   documentation; anything that reports a version must read it from disk.

---

## Roadmap

This repository is mid-refactor from single-machine scripts to something any
nullintosh user can run. Current state and direction:

- [x] Repository structure, licensing, documentation skeleton
- [x] `nvk-doctor` as a machine-agnostic preflight gate
- [x] Steam discovery: multiple library roots, `appmanifest` parsing, executable
      ranking, unix↔Windows path mapping — with offline fixtures
- [x] Per-game profile format, and `nvk-mkapp --regenerate-all` to rebuild every
      launcher after a runtime or CrossOver update
- [x] `nvk-setup`: a guided front door that runs the whole arc
- [ ] File the driver findings upstream — written up ready to send in
      [docs/upstream/](docs/upstream/), not yet submitted
- [ ] A second machine. Everything above is tested; *tested* here means against
      fixtures and one RTX 4070. See [Coverage](#coverage).

Non-Steam sources (Epic, GOG) are out of scope for the first release, but only
discovery assumes Steam: the profile format does not, and `nvk-mkapp` will take
any Windows path.

---

## Coverage

Honest version: **one configuration.** RTX 4070, i7-13700K Hackintosh, macOS 26,
CrossOver 26.3, two games, one of which is the one everything was developed
against.

What that means in practice:

* The parsing is covered by a test suite that runs anywhere, against fixtures
  built to be *unlike* this machine — second volumes, folder names that are not
  game names, Unreal layouts, hostile game names.
* The hardware gate (`nvk-doctor`) is machine-agnostic by construction: it
  reads versions and hashes from disk rather than asserting values, so it
  reports what your machine has rather than what mine had.
* Everything that happens *after* a launcher starts — whether a given game
  runs, how fast, and what it looks like — is one data point.

If you run `nvk-doctor` on another machine, that output is worth more to this
project than any feature request.

---

## Safety

No sudo. No system files are modified. No binaries are shipped. Every change to
a bottle is backed up and reversible with `undo`. `DYLD_*` is set per-process
rather than globally.

---

## License

Scripts and documentation: **MIT**, see [LICENSE](LICENSE).

The NVK runtime these scripts configure is **PolyForm Noncommercial** and
bundles NVIDIA's NGX license. It is **not** included here and must not be
redistributed.
