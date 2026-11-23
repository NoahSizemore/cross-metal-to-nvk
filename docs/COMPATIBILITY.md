# Compatibility

What works, what does not, and which failures are not this project's to fix.

> Coverage is currently **one machine and one game**. Entries below marked
> *verified* were observed directly; everything else is reasoning from the
> architecture and should be treated as a prediction until someone reports
> otherwise.

---

## Verified configurations

| Component | Version |
|---|---|
| GPU | NVIDIA RTX 4070 (AD104, `10de:2786`) |
| CPU / platform | Intel i7-13700K, Hackintosh, OpenCore |
| OS | macOS 26 Tahoe |
| Driver | `/Library/GPUBundles/nvmtl/`, `NVMTLDriver.bundle` 2.9 |
| Vulkan loader | `libvulkan.1.4.362.dylib` |
| NVK reports | Vulkan 1.4.363, `NVIDIA GeForce RTX 4070 (NVK AD104-A)` |
| Wine runtime | `nvk-wine-provider-63e41c4c0cb0` (binary) |
| CrossOver | 26.3.0.39832 |

Every value in that table is one `nvk-doctor` reads from disk rather than one
written down here, with one exception worth knowing about: the runtime binary
reports build `63e41c4c0cb0` while its own `BUILD.json` records
`66fb06568adc`. They are different fields and need not agree; `nvk-doctor`
prints both rather than picking one.

Read your own values with `bin/nvk-doctor` rather than comparing against this
table by eye — runtime builds change underneath the documentation, and have
already done so once: the runtime's `BUILD.json` and the `nvk-runtime` binary
report different build identifiers on the reference machine. `nvk-doctor`
prints both rather than choosing between them.

---

## Games

| Game | Engine | API | Status |
|---|---|---|---|
| Deadlock (1422450) | Source 2 | D3D11 | *Verified playable.* 35–130 fps, low settings, FSR2 2x. |

Deadlock also ships a Vulkan renderer (`rendersystemvulkan.dll`). Running it
with `-vulkan` would drop DXVK from the chain entirely. **Untested** — a
promising experiment for anyone with the stack working.

---

## Anticheat

Games with kernel-level or heavily-integrated anticheat do **not** run under
Wine on macOS. This is not a limitation this project can address.

The tooling checks for you:

```sh
nvk-steam anticheat "$(nvk-steam games Steam | awk -F'\t' '$1 == 1422450 {print $4}')"
```

`nvk-setup` runs this check as a step of its own, says plainly what it found,
and stops unless you pass `--allow-anticheat`. It does not refuse outright —
reports that a specific title fails are useful — but it will not let the
question go unasked.

What it looks for in a game's install directory:

* `EasyAntiCheat*`, `*_EAC*` — EAC
* `BEService*`, `BattlEye*`, `BEDaisy*` — BattlEye
* `vgc.exe`, `vgk.sys` — Riot Vanguard

These binaries are also excluded from the executable picker, so an anticheat
installer can never be chosen as the thing to launch.

If present, expect the game to fail at or shortly after launch regardless of
graphics configuration. Launching it anyway will not damage anything, but the
resulting log is not a graphics bug.

---

## D3D12 and DLSS

`nvk-bottle setup <bottle> --d3d12` installs vkd3d, so D3D12 titles have a
path. **Untested** on the reference machine, because the test game ships only
D3D11 and Vulkan renderers.

Note that a bottle can already contain `d3d12.dll` and `d3d12core.dll` that
CrossOver installed itself. These are vkd3d, but not *the runtime's* vkd3d, and
`nvk-doctor` reports the mismatch as a warning rather than a failure: the
D3D11 path does not depend on them. Running `nvk-bottle setup --d3d12` replaces
them with the pair the runtime ships.

The runtime reports `supports_dlss: true` and ships NGX plus DXVK-NVAPI, but
**DLSS requires D3D12**. It therefore cannot apply to a D3D11-only title no
matter what the runtime advertises. Untested for genuine D3D12 games.

Note that the runtime's own build metadata describes DLSS super-resolution as
*experimental* and frame generation as *unqualified*.

---

## Launching: the two-app split vs `--needs-steam`

The **documented default** is two generated apps:

1. `Steam (NVK)` — starts Steam inside the bottle with the NVK environment
2. `Your Game (NVK)` — launches the game executable directly

`nvk-mkapp --needs-steam` collapses these into one app that starts Steam, waits
for it, then launches the game. It is a convenience and **may not work
everywhere**. Known limits:

* It waits a fixed settling period after Steam appears, which is a guess.
* Readiness is inferred, not reported. The check requires both a `wineserver`
  running for *this* prefix — identified by the prefix's device and inode, so a
  Steam in another bottle does not count — and a `steamwebhelper` process. That
  is much tighter than the system-wide process check it replaced, but two
  bottles both running wine can still confuse it.
* It cannot help with games that refuse to start outside Steam's process tree;
  see below.

### Games that refuse to launch outside Steam

Launching a game executable directly bypasses Steam's bootstrap. Some games
require being started as a child of Steam — typically those with DRM wrappers
or that initialise the Steam API early and exit on failure. Symptoms are an
immediate exit, or a complaint about Steam not running even though it is.

If a game ships `steam_api64.dll` and refuses to start directly, launching it
through Steam's own UI (with the bottle configured via
`nvk-bottle setup --dyld`) is the available workaround.

---

## Platforms not supported

* **Apple Silicon** — no NVIDIA GPU. Use D3DMetal / Game Porting Toolkit.
* **Pre-Turing NVIDIA** — outside the driver's support range.
* **Non-Steam stores** — Epic, GOG and others are not handled by the discovery
  tooling yet. Nothing else assumes Steam: the profile format does not, and
  `nvk-mkapp` takes a Windows path, so a non-Steam game can be set up today by
  writing a profile by hand or passing `--bottle` and `--app` directly. Only
  *finding* the game automatically is Steam-specific.

---

## Contributing a compatibility report

A useful report contains the `bin/nvk-doctor` output, the game and its appid,
which launch method you used, what you set, and what you observed — including
frame rates if the game ran. Reports that a game *fails* are as valuable as
reports that one works, provided the anticheat check above has been ruled out
first.
