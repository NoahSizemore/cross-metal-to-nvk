# Framebuffer compression is refused on every render target

**Component:** NVK memory allocation (`nvk-compress`)
**Severity:** performance — a constant, broad tax rather than a per-feature one
**Affects:** everything that renders

## Environment

```
GPU            NVIDIA GeForce RTX 4070 (AD104, 10de:2786)
CPU / platform Intel i7-13700K, Hackintosh (OpenCore)
OS             macOS 26.7.3 (25G342), x86_64
Driver bundle  NVMTLDriver.bundle 2.9, /Library/GPUBundles/nvmtl/
Vulkan loader  libvulkan.1.4.362.dylib
NVK reports    Vulkan 1.4.363, device "NVIDIA GeForce RTX 4070 (NVK AD104-A)"
Wine runtime   nvk-wine-provider-63e41c4c0cb0 (binary),
               nvk-wine-provider-66fb06568adc (BUILD.json source_runtime_id)
CrossOver      26.3.0.39832
DXVK           3.1.1+nvk, as shipped by the runtime
```

> Captured with `nvk-doctor` from
> <https://github.com/>…/cross-metal-to-nvk. Note that the runtime binary and
> its own `BUILD.json` report different identifiers; both are included because
> it is not clear which one you want.

## What happens

For every render target allocation:

```
unsupported pte_kind(0xb/0xc)
nvk-compress: compressed alloc N refused (-13), falling back uncompressed
```

The fallback is correct — rendering works — but it fires universally, not
occasionally. The GPU runs with memory compression entirely disabled.

## Why this matters more than it looks

An Ada-generation card's bandwidth budget assumes framebuffer compression is
available. Disabling it does not remove a feature; it changes the cost of every
render target read and write for the whole frame. On the reference machine this
is the largest single identified contributor to the gap between this stack and
the same card on Windows.

### Measured evidence that this machine is bandwidth-bound, not compute-bound

Added after profiling Deadlock with `DXVK_HUD=gpuload,drawcalls,descriptors`:

* **`gpuload` sits at ~100% essentially all the time**, with only rare brief
  dips.
* **Raising the quality preset from low to Ultra (with FSR2 2x) costs
  nothing** — identical upper and lower frame-rate bounds.
* **Frame cost scales with draw count, not shader complexity.** `drawcalls` more
  than doubles on detailed views, and frame time roughly doubles with it
  (~9 ms → ~20 ms), while shader quality changes are free.

A GPU pinned at 100% whose ALUs are evidently idle — Ultra shading being free
proves spare arithmetic capacity — is saturated by something other than
arithmetic.

**However, this machine turned out not to be pixel-sensitive, which argues
against compression being the dominant cost.** Reducing render resolution
produced no measurable change, and every available upscaler setting performed
identically. Compression savings scale with render-target pixel traffic, so a
workload indifferent to pixel count is unlikely to be limited primarily by
compressed-vs-uncompressed render targets. What the measurements actually point
at is a per-draw cost (see
[05-descriptor-buffer-unavailable.md](05-descriptor-buffer-unavailable.md)).

This is recorded because an earlier revision of this report claimed the
`gpuload` reading corroborated compression as the leading bottleneck. It does
not. The bug stands on its own terms — it fires on every render target
allocation, 88 times in one 137-line session log — and it is a real,
universally-applied tax. Its *rank* among this stack's costs is simply not
established, and the resolution evidence suggests it is lower than first
assumed.

## What would help

The refusal reports `pte_kind` values `0xb` and `0xc` as unsupported, and
`-13` as the allocation result. Three things would make this diagnosable from
outside:

1. Whether these `pte_kind` values are expected to be unsupported on AD104,
   or whether this is a kernel-side gap.
2. Whether `-13` originates in the NVIDIA open kernel modules or in NVK's own
   allocation path.
3. Whether any configuration currently allows compressed allocations to
   succeed, so that the performance difference can be measured rather than
   estimated.

## Related, and probably not a bug

Presentation performs exactly one full-frame GPU copy per present:

```
gpu_copy_bytes / gpu_copy_count = 14,745,206 bytes per frame
2560 × 1440 × 4                 = 14,745,600 bytes
```

The runtime's own README states that presentation is not zero-copy, so this
appears to be known and intended. It is mentioned only because it is the other
half of the measured performance gap, and the two are easily confused when
reading a profile.
