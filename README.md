# nvk-crossover

Run Windows games in CrossOver on an **Intel Hackintosh** through the **native
NVK** NVIDIA path, instead of CrossOver's default Metal translation.

These are configuration scripts. They ship **no binaries** and redistribute
nothing — you install NullMoth's NVIDIA driver and its Wine/NVK runtime
yourself, and these tools point CrossOver at it.

> **Status: experimental.** Built and verified on a single machine (RTX 4070,
> macOS 26 Tahoe, CrossOver 26.3). The runtime's author does not qualify
> commercial CrossOver. Treat performance numbers below as one data point, not
> a promise.

---

## What this is not

* **Not a driver.** You install the NullMoth driver 3.0+ *including its Wine
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

* Intel Mac or Hackintosh (x86_64), macOS 15.5+ or Tahoe 26
* NVIDIA Turing or newer
* NullMoth driver 3.0+ **including the Wine runtime** at
  `/Library/GPUBundles/nvmtl/wine`
* CrossOver (verified against 26.3)

Verify the runtime before anything else:

```sh
/Library/GPUBundles/nvmtl/wine/bin/nvk-runtime check /Library/GPUBundles/nvmtl/wine
```

---

## Quick start

```sh
git clone <this repo> && cd nvk-crossover

# 1. Check the machine. Read-only; changes nothing.
./bin/nvk-doctor

# 2. Configure a bottle. Installs the runtime's DXVK into the prefix and
#    writes the Wine environment block into cxbottle.conf, backing it up first.
#    Quit all applications in the bottle before running this.
./bin/nvk-bottle setup Steam

# 3. Generate launchers. The two-app split is the documented default:
#    one app to start Steam under NVK, one for the game itself.
./bin/nvk-mkapp --bottle Steam \
  --app 'C:\Program Files (x86)\Steam\steam.exe' --name 'Steam (NVK)'

./bin/nvk-mkapp --bottle Steam \
  --app 'C:\...\game\bin\win64\yourgame.exe' \
  --name 'Your Game (NVK)' --args '-dx11'
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
| [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) | Per-game notes, anticheat, Steam launch caveats |

---

## Repository layout

```
bin/
  nvk-doctor        preflight check and bug-report dump (read-only)
  nvk-bottle        setup / run / status / undo for a CrossOver bottle
  nvk-mkapp         generates .app launchers
  vk-icd-probe.py   enumerates the NVK ICD via ctypes; no Vulkan SDK needed
profiles/           per-game profiles (launch args, dxvk fragments, known issues)
tests/fixtures/     sample Steam manifests for testing discovery logic offline
docs/               shipping documentation
```

---

## Design rules

These are constraints, not preferences. Changes that violate them are bugs.

1. **Never redistribute the runtime.** It is PolyForm Noncommercial and bundles
   NVIDIA's NGX license. Scripts only; verify the user's copy with
   `nvk-runtime check`.
2. **Never require sudo.** Nothing here needs it, and the scripts refuse to run
   as root.
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
- [ ] `nvk-doctor` as a machine-agnostic preflight gate (currently hardcoded to
      one bottle and one game)
- [ ] Steam discovery: multiple library roots, `appmanifest` parsing, executable
      ranking, unix↔Windows path mapping — with offline fixtures
- [ ] Per-game profile format, and `nvk-mkapp --regenerate-all` to rebuild every
      launcher after a runtime or CrossOver update
- [ ] `nvk-setup`: a guided front door that runs the whole arc
- [ ] File the driver findings upstream

Non-Steam sources (Epic, GOG) are out of scope for the first release, but the
profile format does not assume Steam.

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
