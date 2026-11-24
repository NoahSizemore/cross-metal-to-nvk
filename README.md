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
* **Icons are found automatically.** `nvk-mkapp` asks `nvk-icon` for one when
  `--icon-from` is not given: first the `.icns` CrossOver extracted from the
  real executable (`CrossOver/Programs/<bottle>/<Game>.app`), then Steam's
  library artwork for the appid, converted with `sips` and `iconutil`. Both
  ship with macOS, so there is nothing to install.
* `nvk-mkapp --icon-from '/path/to/some.app'` overrides that with a specific
  icon. `nvk-icon sources ...` lists every candidate it found, best first.
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

One measured data point: **Deadlock**, RTX 4070, FSR2 2x, 1920×1080 — **88
frames per second actually presented**, read from the kext's own counters. The
in-game overlay reported 45–195 fps across the same session; the gap is frames
rendered and then discarded.

**Quality settings are effectively free.** Ultra preset produced the same
frame-rate bounds as low, at no measurable cost, so GPU shading is not the
limiting factor. Run it on Ultra.

**Turn on the driver's experimental features.** Three of them are off by default
and measurably help; this is the single most effective change available:

```sh
sudo /Library/NullMoth/nullmoth-setup.sh --experimental gameprio,tile,tgp
```

* `gameprio` — the one unambiguous win. Frame-time spikes fell from 41 ms to
  10–15 ms and mean frame time by 27%, against a known-off baseline.
* `tgp` — enables TGP power management, which ships **off**, so the GPU boost
  daemon has no framework to act through without it. Needs a reboot.
* `tile` — tiled shading.

`tgp` and `tile` each *cost* light-scene frame time relative to `gameprio` alone
and pay it back in heavy scenes (40–43 fps, noticeably steadier, against roughly
37–38 at baseline). Whether that trade is worthwhile is **not settled** — heavy
scenes were never measured with `gameprio` by itself. If you are reproducing
this, measure that case and you will know more than we do.

Do **not** enable `icb`. It drives GPU utilisation to ~97% while making both
frame time and fps *worse* — a busier GPU doing less useful work. Utilisation is
only meaningful read alongside frame time, never on its own.

That script — `/Library/NullMoth/nullmoth-setup.sh`, part of the driver, not
this project — is the driver's own tuning surface and is undocumented in its
README. `--gpu-boost`, `--game-mode` and `--experimental` all live there, and
most of it ships off.

There are two regimes, with different limits:

| Scene | Frame time | GPU load | Limited by |
|---|---|---|---|
| light geometry | ~3–4 ms | 50–60% | CPU / submission — the GPU is idling |
| dense geometry | up to ~20 ms | ~100% | GPU, scaling with draw count |

Frame cost tracks **how many things are drawn**, not how expensive they are to
shade and not how many pixels they cover — reducing render resolution and
changing upscalers both measured as no-ops. That is a per-draw cost, which is
why it shows up on the CPU in one regime and the GPU in the other.

What actually limits it, in rough order:

1. **Framebuffer compression is refused on every render target.** The driver
   logs `unsupported pte_kind` and falls back uncompressed — a constant tax on
   all render-target traffic, which is the binding constraint here.
2. **DXVK runs on its legacy binding model**, because
   `VK_EXT_descriptor_buffer` is not available. Draw calls and descriptor-set
   counts both rise with scene detail, and frame time rises with them.
3. **Scene-transition spikes of 100–150 ms** from pipeline creation, even with
   the Mesa shader cache warm.
4. **Most rendered frames never reach the display.** An application asking for
   `IMMEDIATE` is told it was granted, then gets vsync behaviour, and the
   discarded frames are not reported anywhere it can see them.
5. **One full-frame GPU copy per present.** Measured at exactly
   2560×1440×4 bytes per frame; presentation is not zero-copy. Once timed, its
   direct cost is only ~0.4–0.5 ms per frame, so it ranks lower than it looks.
   Note it tracks the **desktop** resolution, not the game's — a game set to
   1080p on a 1440p desktop still presents a 1440p swapchain.

What actually helped, measured: dropping to 1920×1080 roughly doubled the
frame-rate floor. Lowering the display refresh rate made things worse. **No
graphics or DXVK setting tested has produced an effect distinguishable from
noise** — identical configurations have produced results 35% apart on real
gameplay, so read [CHANGELOG.md](CHANGELOG.md) before trusting any small
improvement, including your own.

Three things worth knowing before you tune:

* **`-vulkan` does not work.** Source 2's native Vulkan renderer would remove
  DXVK from the chain, but swapchain creation fails. See
  [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).
* **GPU clocks cannot be read on this stack.** No sysctl reports them. Check
  that `-nvrmnopm` is absent from your boot-args, then use resolution scaling
  as an indirect test.
* **Do not judge a change by the FPS overlay.** It reports rendered frames, and
  most of them are discarded before reaching the display. Use
  `bin/nvk-flipstat`.

`bin/nvk-flipstat begin` / `end` measures the presentation path around a
session. See [docs/DRIVER-ISSUES.md](docs/DRIVER-ISSUES.md) for the full
write-ups, including two driver bugs that cause silent visual corruption, and
[CHANGELOG.md](CHANGELOG.md) for what has been ruled out.

---

## Documentation

| Document | Contents |
|---|---|
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptoms, causes, fixes |
| [docs/DRIVER-ISSUES.md](docs/DRIVER-ISSUES.md) | Upstream driver findings with reproduction detail |
| [docs/upstream/](docs/upstream/) | The same findings, written as reports ready to submit |
| [CHANGELOG.md](CHANGELOG.md) | What changed, and what was measured or ruled out |
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
  nvk-icon          finds an icon for a launcher and converts it to .icns;
                    nvk-mkapp calls it when --icon-from is not given
  nvk-flipstat      reads the kext's presentation counters; begin/end deltas
                    them around a session (read-only)
  nvk-mdmp          reads a Windows minidump: exception, graphics modules, and
                    the engine's own fatal-error report
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
- [x] Automatic launcher icons, from CrossOver's extracted `.icns` or Steam's
      library artwork (`nvk-icon`)
- [x] Instrumentation that does not need a GPU vendor tool: `nvk-flipstat` for
      presented frames, `nvk-mdmp` for reading crash dumps on macOS
- [ ] File the driver findings upstream — six written up ready to send in
      [docs/upstream/](docs/upstream/), none submitted
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
