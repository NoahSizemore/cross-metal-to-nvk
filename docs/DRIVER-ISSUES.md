# Driver issues

Findings about the NullMoth driver and its NVK runtime that are **not** bugs in
this repo's scripts. Each was observed directly in logs on the reference
machine. None had been reported upstream as of this writing.

Where a finding names a version, that version is the one it was observed on.
Check your own with `bin/nvk-doctor` rather than assuming these still apply.

---

## 1. The AIR translator rejects texture atomics

**Impact:** breaks any D3D11 game using FSR2 on the Metal translation path.
Does not affect the native NVK path this repo configures.

The translator writes a refusal to `/Library/GPUBundles/nvmtl/failed-air/` as
`main0-<hash>.ll`, whose first line reads:

```
; translator refusal (kernel): air.atomic_fetch_add_explicit_texture_2d.u.v4i32
  value must be a four-lane i32 vector
```

The shader is FSR2's Compute Luminance Pyramid (FidelityFX SPD) — identifiable
by `cbFSR2_t`, `spdIntermediateA/B/G/R` and `rw_spd_global_atomic`. Two
instructions in a 2,445-line shader.

**Why this is a translator bug:** the AIR module was emitted by Apple's own
Metal compiler, so it is valid by construction. The translator is over-strict.

### The diagnostic is invisible by default

`/Library/GPUBundles/` is root-owned and the `failed-air` directory does not
exist out of the box. The driver probes writability first (it creates
`.probe-<pid>`), finds it cannot write, and silently discards the dump. Users
therefore never see the driver's own best diagnostic.

```sh
sudo mkdir -p /Library/GPUBundles/nvmtl/failed-air
sudo chown "$(id -un)":staff /Library/GPUBundles/nvmtl/failed-air
```

This is the one place the project knowingly mentions `sudo`, and it is a
one-time diagnostic opt-in, never something the scripts do for you.

---

## 2. sRGB formats cannot be storage images — silently

**Impact:** silent data loss. Shader writes vanish, producing black or frozen
frames with nothing in the log unless you are looking for it.

```
newTextureWithDescriptor: pixel format 71/81 asked for ShaderWrite and NVK
cannot make it a storage image — shader writes to it will be LOST
```

Format 71 is `RGBA8Unorm_sRGB`, 81 is `BGRA8Unorm_sRGB`.

**Root cause:** Vulkan defines no `STORAGE_IMAGE` feature bit for sRGB formats;
Metal permits it. The driver bridges the two and loses the writes. The honest
behaviours would be to refuse the texture creation, or to write through a
linear view — not to accept and discard.

---

## 3. Framebuffer compression is refused on every render target

**Impact:** the largest known fixable performance item among the bandwidth
costs. See the presentation note below for why the per-present copy, once
measured, turned out not to compete with it.

```
unsupported pte_kind(0xb/0xc)
nvk-compress: compressed alloc N refused (-13), falling back uncompressed
```

This fires on every render target, meaning the GPU runs with all memory
compression disabled. On a card whose bandwidth budget assumes compression,
this is a broad, constant tax rather than a per-feature one.

---

## 4. A game-driven Vulkan swapchain cannot be created

**Impact:** blocks any Windows game that uses the Vulkan API directly instead
of reaching it through DXVK or vkd3d. Does not affect the D3D11 path.

```
ERROR! VK call failed! result = Unknown VkResult value ( vkCreateSwapchainKHR(...) )
Failed to initialize video!
FATAL ERROR: AppSystemDict: Error in Init() of interface 'RenderDeviceMgr001'!
```

Observed on Deadlock and Counter-Strike 2 with `-vulkan`. Everything up to
presentation works — the real vendor ID `0x10de` is reported, so this is native
NVK with DXVK out of the chain — and then one call fails.

Two things make this worth reading before you try it yourself:

* **The returned `VkResult` is not a value in the enum.** "Unknown VkResult
  value" is the engine failing to name the code it was given. A correct refusal
  would have identified which field of `VkSwapchainCreateInfoKHR` was at fault.
* **The crash looks worse than it is.** Exception `0x80000003 BREAKPOINT` in
  `kernelbase.dll` is the engine's deliberate abort path, not a memory fault.

The diagnostic is not in `console.log` — the process dies before log flushing.
It is in the minidump beside the game executable. Read it with `bin/nvk-mdmp`.

Note that the runtime's own README scopes support to "an x64 Windows D3D11 or
D3D12 game", so this configuration was never qualified.

---

## 5. `VK_EXT_descriptor_buffer` is unavailable

**Impact:** CPU-side cost on every draw call, for every title.

```
info:  VK_EXT_descriptor_buffer:
info:    descriptorBuffer               : 0
info:  Binding model: Legacy
```

DXVK implements both descriptor paths and prefers descriptor buffers when
offered. They are not offered here, so every title runs on the legacy
descriptor-pool path. This is not a setting you can change.

It is listed separately from finding 3 because it is a different *kind* of
cost. Compression and the presentation copy are bandwidth; this is per-draw CPU
work on the submission thread. On the reference machine, dropping resolution
raised the frame-rate floor substantially but did not move the ceiling at all —
the signature of a per-submission cost rather than a bandwidth one.

---

## Related: the presentation copy

Not a bug, but the other half of the performance gap. Measured on the reference
machine:

```
gpu_copy_bytes / gpu_copy_count = 14,745,206 bytes per frame
2560 × 1440 × 4                 = 14,745,600 bytes
```

Exactly one full-frame GPU copy per present. The runtime's own README states
that presentation is "not zero-copy", so this is known and intended for now.

**The copy follows the desktop resolution, not the game's.** A session
configured for 1920×1080 — via `-w 1920 -h 1080` and `video.txt` — still
created a 2560×1440 swapchain, because Source 2 in fullscreen takes a
display-sized swapchain and renders internally at the chosen resolution:

```
info:    Buffer size:  2560x1440
NVK Bridge: swapchain 2560x1440, 3 Vulkan images, 3 Metal slots
```

So lowering the game's resolution does **not** reduce the per-present copy,
contrary to what earlier versions of these notes claimed. The measured
1440p→1080p gain (frame-rate floor 35 → 70 fps) was a reduction in render cost
alone. To shrink the copy you have to change the **desktop** display mode.

`bin/nvk-flipstat` measures this path from the kext's own counters. Snapshot
with `begin`, play, then `end`.

**Measured, and it is not as expensive as it looks.** Mean time in flip tracks
the display refresh interval rather than pixel count — 3.18 ms at 180 Hz
against 5.17 ms at 120 Hz, in both cases 57–62% of one refresh interval, where
an even phase distribution alone accounts for 50%. Only the residue above half
an interval can be work: **0.4–0.5 ms per frame, about 4% of wall clock.** The
copy is real; its direct time cost is minor.

Presentation is nonetheless vsync-latched — `flip_interval = 1`, and
`flip_latch_waits` tracks `flip_n` one-for-one. The consequence that holds is
that **most rendered frames never reach the display**: overlay readings of
195–240 fps against 61–88 frames actually presented, with `flip_latch_late` at 0
because the surplus is coalesced in the drawable queue rather than counted as
dropped. Measure with `nvk-flipstat`, not with an FPS overlay.

> **An earlier version of this section claimed presented frame rates are
> quantised to `refresh / n`, and that this caused the frame pacing problems on
> the reference machine. Per-frame inspection with DXVK's `frametimes` overlay
> disproved it** — the distribution is smooth and scene-dependent, not banded.
> The aggregate counters here cannot distinguish the two, which is how the claim
> survived as long as it did. The real pacing problem is scene-transition
> stalls of ~1000 ms, documented in [../CHANGELOG.md](../CHANGELOG.md), and it
> is not a presentation issue.

**Read the driver's own documentation before theorising about this.** Every
`debug.nvrm*` sysctl carries a description:

```sh
sysctl -d debug.nvrmfb_flip_latch
sysctl -a | grep -E '^debug\.nvrm' | cut -d: -f1 | xargs -n1 sysctl -d
```

Two things that matters for:

* `flip_interval` is a *minPresentInterval*, and its description ends "tearing
  stays off". `1` already permits a flip per vblank, so it is not the throughput
  cap, and `0` would not unsynchronise anything.
* `flip_latch` is the serialisation: `1` makes a committed flip wait for
  completion before its surface retires, and `flip_latch_waits` tracks `flip_n`
  one-for-one here. Its documented alternatives are `0` (labelled a debug
  bypass) and `2` (deferred — the next submit verifies instead).

`flip_latch = 2` is therefore the one documented knob worth trying, and it is
writable by root. **Untested here.** Nothing in this repository writes it.

Note also that `flip_n` counts *pure* (zero-copy) flips while the NVK bridge
reports `presentation=gpu-copy` for games, so flip rate is the display flip
path rather than the game's Vulkan presents. Calibrate before relying on it:
cap the game with `fps_max` and check that `nvk-flipstat` tracks the cap.

The same tool is the answer to a question that comes up often: **there is no way
to read GPU clocks on this stack.** The kext exposes no clock, pstate, voltage
or frequency sysctl, and `powermetrics` does not know this GPU. Check that
`-nvrmnopm` is absent from your boot-args (it disables power management), then
use resolution scaling as an indirect test — a GPU pinned at idle clocks would
be hard bandwidth-bound and its *ceiling* would scale with resolution.

---

## Reporting these upstream

All five are written up as submission-ready reports in
[upstream/](upstream/) — environment, observation, the driver's own diagnostic
quoted verbatim, and what the honest behaviour would be. **They have not been
submitted.**

If you send one, re-run `bin/nvk-doctor` first and replace the environment
block. The versions in those reports were read from one machine on one day, and
the runtime has already moved underneath this documentation once: the
`nvk-runtime` binary and its own `BUILD.json` currently disagree about which
build they are.

Quote the driver's diagnostic text exactly. It is precise, and paraphrasing it
loses the detail that makes each of these actionable.
