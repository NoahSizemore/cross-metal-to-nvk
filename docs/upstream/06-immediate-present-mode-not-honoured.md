# VK_PRESENT_MODE_IMMEDIATE_KHR is granted but presentation stays vsync-latched

**Component:** Wine/NVK presentation bridge and the kext flip path
**Severity:** conformance, with a performance cost — an application is told its
requested present mode was granted when it was not, and the resulting discarded
frames are not reported anywhere it can see them
**Affects:** every title

## Environment

```
GPU            NVIDIA GeForce RTX 4070 (AD104, 10de:2786)
CPU / platform Intel i7-13700K, Hackintosh (OpenCore)
OS             macOS 26.7.3 (25G342), x86_64
Driver bundle  NVMTLDriver.bundle 2.9, /Library/GPUBundles/nvmtl/
Vulkan loader  libvulkan.1.4.362.dylib
NVK reports    device "NVIDIA GeForce RTX 4070 (NVK AD104-A)", NVK 26.3.1
Wine runtime   nvk-wine-provider-63e41c4c0cb0 (binary),
               nvk-wine-provider-66fb06568adc (BUILD.json source_runtime_id)
CrossOver      26.3.0.39832
DXVK           3.1.1+nvk, as shipped by the runtime
Display        2560×1440 @ 180 Hz, plus 1080×1920 @ 165 Hz rotated
Boot-args      no -nvrmnopm (power management not disabled)
```

## What happens

DXVK requests an unsynchronised present mode, and the implementation **grants
it**:

```
info:  Presenter: Actual swapchain properties:
info:    Format:       VK_FORMAT_B8G8R8A8_UNORM
info:    Color space:  VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
info:    Present mode: VK_PRESENT_MODE_IMMEDIATE_KHR (dynamic: no)
info:    Buffer size:  2560x1440
info:    Image count:  3
NVK Bridge: swapchain 2560x1440, 3 Vulkan images, 3 Metal slots
```

Three images, three Metal slots, `IMMEDIATE` reported as the active mode. The
application has asked not to be synchronised to vblank and the Vulkan layer has
agreed.

Presentation is nevertheless synchronised to vblank. From the kext's own
counters, over a 185-second session:

```
debug.nvrmfb_flip_interval      1
debug.nvrmfb_flip_n             16350
debug.nvrmfb_flip_latch_waits   16358
debug.nvrmfb_flip_latch_late    0
debug.nvrmfb_flip_latch_deferred 0
```

Every flip waits on a latch — `flip_latch_waits` tracks `flip_n` one-for-one,
in every session measured. `IMMEDIATE` is honoured at the API level and ignored
at the presentation layer, where the behaviour is indistinguishable from `FIFO`.

**The driver documents this directly.** Its own sysctl descriptions, read with
`sysctl -d`, state that the flip path does not tear by construction:

```
debug.nvrmfb_flip_interval  minPresentInterval of the pure (zero-copy) flip;
                            tearing stays off
debug.nvrmfb_flip_latch     1 = a committed flip waits for its completion
                            before a surface retires (0 = debug bypass,
                            2 = deferred: the next submit verifies it)
debug.nvrmfb_flip_latch_late
                            presents skipped because the previous flip was
                            still on its way to the panel
```

"Tearing stays off" is the crux: an untearing presentation path cannot implement
`VK_PRESENT_MODE_IMMEDIATE_KHR`, whose defining property is that it does not
wait for vblank. The mode is accepted and reported as active anyway.

Note also that `flip_latch_late` is **0** in every session measured, so the flip
path is not reporting skipped presents. Frames beyond the flip rate are being
coalesced in the three-slot drawable queue rather than counted as dropped, which
is why an application cannot detect the loss.

## The observable consequence

A majority of rendered frames are discarded. DXVK's overlay reported 195–240 fps
during sessions that presented 61–88 frames per second, measured from the kext
counters over five ~190-second Deadlock sessions at 1920×1080. The CPU and GPU
work to produce the surplus is spent and thrown away, and because
`flip_latch_late` stays at 0 the loss is not reported anywhere an application
could see it — the frames are coalesced in the three-slot drawable queue.

**What this report does not claim.** An earlier draft argued that presented
frame rates are quantised to `refresh / n` and that this was the cause of
visible judder. Per-frame inspection with DXVK's `frametimes` overlay does not
support that: the distribution is smooth and scene-dependent, not banded at
multiples of the refresh interval. That argument has been withdrawn. Frame
pacing on this stack is dominated by scene-transition stalls of a different
origin, which are not a presentation issue — the slowest flip recorded since
boot is 26.6 ms against stalls three orders of magnitude larger.

What remains is the conformance problem: an application that asks for
`IMMEDIATE` is told it has been granted, and then gets `FIFO` behaviour plus
silent frame coalescing. That is worth fixing on its own terms, independently of
how much performance it costs on any particular machine.

## What was ruled out

* **Not the application requesting vsync.** The game sets `mat_vsync 0`, and
  DXVK was additionally configured with `dxgi.syncInterval = 0`. The presenter
  block above is from that run.
* **Not DXVK selecting `FIFO` as a fallback.** It reports `IMMEDIATE` as the
  actual mode.
* **Not insufficient buffering.** Three swapchain images, three Metal slots.
* **Not a missed-deadline artefact being reported as such.**
  `flip_latch_late` and `flip_latch_deferred` are both 0 across every session,
  and `flip_latch_timeouts` has reached 1 since boot. The latch wait is the
  normal path, not an error path.
* **Not power management.** `-nvrmnopm` is not set.

## What would help

1. Whether `VK_PRESENT_MODE_IMMEDIATE_KHR` (and `MAILBOX`) are intended to be
   functional on this bridge, or are advertised and accepted while the Metal
   presentation path always latches to vblank. If the latter, advertising only
   `FIFO` would at least let applications and layers make correct decisions.
2. Whether the vblank latch is required by the Metal drawable path — that is,
   whether an unsynchronised present is achievable at all through
   `CAMetalLayer`/`nextDrawable`, or whether this is a platform constraint
   rather than an implementation gap. A statement either way closes the question.
3. Whether `debug.nvrmfb_flip_latch = 2` ("deferred: the next submit verifies
   it") is a supported configuration for interactive use, and what it costs. It
   is the only documented knob that removes a serialisation on the flip path
   without being labelled a debug bypass. `flip_interval = 0` appears not to be
   the relevant control, since `1` already permits a flip per vblank and the
   description says tearing stays off either way.
4. Whether `VK_KHR_present_wait` / `VK_KHR_present_id` could be exposed. With
   presentation latched and no present-wait, an application cannot pace itself
   to the real present cadence even in principle, which is why so much rendered
   work is discarded.

## Reproducing

```sh
# Configure for the diagnostic, then launch any D3D11 title.
./bin/nvk-bottle setup <bottle> --log-level debug \
  --dxvk-config 'dxgi.syncInterval = 0'

grep -A 6 'Actual swapchain properties' ~/Library/Logs/nvk-<app>.log
```

Then measure the presented rate, which is not what an FPS overlay reports:

```sh
./bin/nvk-flipstat begin    # play a few minutes
./bin/nvk-flipstat end
```

Compare `mean flip rate` against the display's refresh rate divided by small
integers. `bin/nvk-flipstat` reads only the `debug.nvrmfb_*` and `debug.nvrm_*`
sysctls and needs no privileges.
