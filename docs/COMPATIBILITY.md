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
| Driver | NullMoth 3.0, `/Library/GPUBundles/nvmtl/` |
| CrossOver | 26.3.0.39832 |

Read your own values with `bin/nvk-doctor` rather than comparing against this
table by eye — runtime builds change underneath the documentation.

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

Watch for these in a game's install directory:

* `EasyAntiCheat*` — EAC
* `BEService*`, `BattlEye*` — BattlEye
* `vgk.sys` — Riot Vanguard

If present, expect the game to fail at or shortly after launch regardless of
graphics configuration. Launching it anyway will not damage anything, but the
resulting log is not a graphics bug.

---

## D3D12 and DLSS

`nvk-bottle setup <bottle> --d3d12` installs vkd3d, so D3D12 titles have a
path. **Untested** on the reference machine, because the test game ships only
D3D11 and Vulkan renderers.

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

* The readiness check greps for a `steamwebhelper` process system-wide, so it
  can be fooled by a Steam running in a *different* bottle.
* It waits a fixed settling period after Steam appears, which is a guess.

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
* **Non-Steam stores** — Epic, GOG and others are not handled by the tooling
  yet. The underlying approach is store-agnostic; only the discovery code is
  Steam-specific.

---

## Contributing a compatibility report

A useful report contains the `bin/nvk-doctor` output, the game and its appid,
which launch method you used, what you set, and what you observed — including
frame rates if the game ran. Reports that a game *fails* are as valuable as
reports that one works, provided the anticheat check above has been ruled out
first.
