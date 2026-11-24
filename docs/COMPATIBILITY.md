# Compatibility

What works, what does not, and which failures are not this project's to fix.

> Coverage is currently **one machine and two games played**. Entries below marked
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
| Deadlock (1422450) | Source 2 | D3D11 | *Verified playable.* **Ultra** preset, FSR2 2x, 1920×1080: ~88 frames/s presented, ~3.8 ms in light scenes, 40–43 fps in dense geometry. |
| Counter-Strike 2 (730) | Source 2 | D3D11 | *Starts and renders.* Not benchmarked. |
| Valheim (892970) | Unity | D3D11 | *Not run.* Ships EasyAntiCheat; see Anticheat below. |
| Deadlock / CS2 with `-vulkan` | Source 2 | Vulkan | **Fails.** Swapchain creation refused; see below. |

Two levers matter, in this order.

**Turn on the driver's experimental features** — they are off by default and
they are the largest measured improvement:

```sh
sudo /Library/NullMoth/nullmoth-setup.sh --experimental gameprio,tile,tgp
```

`gameprio` alone cut frame-time spikes from 41 ms to 10–15 ms. See the README
for what each does and why `icb` must be left off.

**Then resolution.** 2560×1440 → 1920×1080 roughly doubled the frame-rate floor.
Quality presets are effectively free on this stack, so lower the resolution
before you lower the settings — Ultra costs nothing that low does not.

### Native Vulkan (`-vulkan`) does not work

Both Source 2 titles ship `rendersystemvulkan.dll`, and running them with
`-vulkan` drops DXVK from the chain entirely. It is the right idea and it does
not work: the engine aborts during presentation setup.

```
ERROR! VK call failed! result = Unknown VkResult value ( vkCreateSwapchainKHR(...) )
Failed to initialize video!
FATAL ERROR: AppSystemDict: Error in Init() of interface 'RenderDeviceMgr001'!
```

You will see a dock icon, nothing on screen, and exit status 1. Nothing is
written to `console.log`, because the process aborts before log flushing.

**If you want to retry this on your own machine** — worth doing, since it is one
machine's result against an unqualified configuration — the flag goes in
`--args`, not into Steam's launch options, which a generated launcher bypasses:

```sh
./bin/nvk-mkapp --profile profiles/deadlock-1422450.conf --args '-vulkan'
```

Then read the engine's own report out of the dump it leaves beside the
executable:

```sh
./bin/nvk-mdmp '<game>/game/bin/win64/deadlock_<date>_<time>_0_error.mdmp'
```

Already ruled out on the reference machine, so you need not repeat it: the flag
takes effect (`Render system: Vulkan`, real vendor ID `0x10de`); device creation
succeeds; the renderer module and `shaders_vulkan_*.vpk` both ship in the
Windows depot; `vulkan-1.dll` and `winevulkan.dll` both load; and forcing
`-w 1920 -h 1080` changes nothing. The `0x80000003 BREAKPOINT` exception is the
engine's deliberate abort, not a memory fault.

Write-up in
[upstream/04-native-vulkan-swapchain-creation-fails.md](upstream/04-native-vulkan-swapchain-creation-fails.md).
Note that the runtime's README scopes support to "an x64 Windows D3D11 or D3D12
game", so a game driving `VK_KHR_swapchain` itself was never qualified — this is
an unsupported configuration failing, not a regression.

### Deadlock requires Steam to be running already

Deadlock **crashes on boot** if Steam is not already up, even with
`needs_steam=yes` — which starts Steam, waits for a `wineserver` and a
`steamwebhelper` for this prefix, then settles before launching. That is not
sufficient for this title. Launching **Steam (NVK)** first, letting it come up,
then launching the game works reliably.

So the two-app split is not merely the documented preference here, it is
required, and this is a concrete instance of the `--needs-steam` caveat below
rather than a hypothetical one. It also constrains diagnostics: any test that
calls for "Steam fully closed" cannot be run on Deadlock.

### Renderer choice and Steam's launch-option prompt

Some games ask which renderer to use through a prompt that Steam shows when you
press Play. A generated `.app` launches the executable directly and therefore
never sees that prompt. Pass the flag in `--args` instead. This is a property of
the two-app split, not a bug, and it is easy to mistake for one.

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
