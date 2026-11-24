# VK_EXT_descriptor_buffer is unavailable, forcing DXVK onto its legacy binding model

**Component:** NVK feature exposure
**Severity:** performance — affects every draw call, on every title
**Affects:** all D3D11 and D3D12 rendering through this stack

> Filed as a question rather than an assertion. It is not clear from outside
> whether this extension is absent by design on this build, absent because the
> Metal-backed allocation path cannot support it, or simply not yet wired up.
> The answer determines whether this is worth pursuing at all.

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
```

## What happens

DXVK queries the device and finds neither descriptor extension:

```
info:  VK_EXT_descriptor_buffer:
info:    descriptorBuffer               : 0
info:  VK_EXT_descriptor_heap:
info:    descriptorHeap                 : 0
```

and consequently selects its fallback descriptor path:

```
info:  Binding model: Legacy
```

The legacy binding model allocates and updates `VkDescriptorSet` objects
through descriptor pools. `VK_EXT_descriptor_buffer` instead lets descriptors be
written directly into a mapped buffer, which removes per-draw set allocation and
most descriptor update traffic. DXVK implements both and prefers the latter when
it is offered.

This is not a tuning choice. The extension is not advertised, so the fallback is
the only path available.

## Why it is being reported

The performance gap on this stack is already accounted for by two known items —
framebuffer compression refused on every render target
([03](03-framebuffer-compression-refused.md)) and one full-frame copy per
present. Both are bandwidth costs. The legacy binding model is a different kind
of cost: CPU-side, per draw call, and paid on the submission thread.

## Measured evidence that cost tracks draw count, not shading

Deadlock profiled with `DXVK_HUD=gpuload,drawcalls,descriptors,frametimes`:

| Observation | Reading |
|---|---|
| `gpuload` | ~100% essentially always |
| quality preset low → Ultra (FSR2 2x) | **no measurable cost** |
| render resolution reduced (`mat_viewportscale`, upscaler presets) | **no measurable cost** |
| every available upscaler type | performed identically |
| `drawcalls`, simple view → detailed view | **more than doubles** |
| frame time, simple view → detailed view | ~9 ms → ~20 ms |
| `descriptors` | rises with scene detail |
| `NVK_DESC_QUARANTINE=0` | large regression, plus visual quality loss |

The pattern is that frame cost follows **how many things are drawn**, not how
expensive each is to shade. Shader quality is free; draw count is not. And
`descriptors` rising alongside `drawcalls` is the legacy binding model doing
exactly what it has to do without descriptor buffers — allocate and update
descriptor sets as draw count grows.

The elimination is what makes this strong: frame cost is **insensitive to pixel
count** (render-resolution reductions and every upscaler option changed
nothing), **insensitive to shader complexity** (Ultra is free), and
**proportional to draw count**.

There are two regimes, and a per-draw descriptor cost is the one explanation
that accounts for both:

| Regime | Frame time | `gpuload` | Limited by |
|---|---|---|---|
| light geometry | ~9 ms (≈110 fps) | 50–60% | CPU / submission; the GPU idles |
| normal to heavy | 9 → 20 ms | ~100% | GPU, scaling with draw count |

A ceiling of ~110 fps while the GPU sits at 50–60% means work cannot be
submitted fast enough. Below that ceiling the GPU saturates, and its cost tracks
draw count rather than shading. Without `VK_EXT_descriptor_buffer`, descriptor
sets cost **CPU** time to allocate and update *and* **GPU** time to bind — which
is precisely a cost that appears on both sides and scales with draw count on
each.

One further data point, offered cautiously: setting `NVK_DESC_QUARANTINE=0`
produced a *large* performance regression and visible quality degradation rather
than an improvement. That suggests the descriptor path is both on the critical
path and doing something load-bearing for correctness. It is mentioned because a
reader might otherwise try it as an optimisation; it is not one.

An earlier version of this report argued the opposite — that a CPU-side ceiling
was indicated, because dropping resolution from 2560×1440 to 1920×1080 doubled
the frame-rate floor without moving the ceiling. `gpuload` at 100% contradicts
that reading, and it is withdrawn. The conclusion that descriptor handling is
implicated survives on the draw-count evidence above, which is stronger.

## Related gaps on the same device

Each of these also pushes DXVK onto a slower or less direct path:

```
VK_EXT_memory_priority         memoryPriority            : 0
VK_EXT_pageable_device_local_memory
                               pageableDeviceLocalMemory : 0
VK_KHR_present_wait            presentWait               : 0
VK_KHR_present_id              presentId                 : 0
VK_EXT_full_screen_exclusive   extFullScreenExclusive    : 0
```

The memory layout is also unusually constrained — two memory types, with no
`DEVICE_LOCAL | HOST_VISIBLE` type at all:

```
info:  Memory:
info:    Heap 0: 11.99 GiB (DEVICE_LOCAL)
info:      Type  0: DEVICE_LOCAL
info:    Heap 1: 24.0 GiB
info:      Type  1: HOST_VISIBLE | HOST_COHERENT | HOST_CACHED
```

With no host-visible device-local type, every upload is staged through host
memory and copied, so there is no resizable-BAR-style direct write path. This is
likely inherent to the Metal-backed allocator rather than a gap, and is noted
only because it compounds with the above.

## What would help

1. Whether `VK_EXT_descriptor_buffer` is expected to be available on this
   driver, and if not, whether the obstacle is the Metal-backed allocation path
   or merely implementation order.
2. Whether `VK_EXT_memory_priority` and `VK_EXT_pageable_device_local_memory`
   are similarly out of reach, since they govern residency decisions that
   currently cannot be expressed.
3. Whether `VK_KHR_present_wait` / `VK_KHR_present_id` could be exposed. These
   are cheap relative to the others and would let DXVK pace frames rather than
   infer timing, which matters more on a presentation path that already performs
   a full-frame copy.

## A note for anyone configuring this stack

The reference configuration sets `dxvk.enableDescriptorBuffer = False`
explicitly. Given that the extension is not advertised, that setting should now
be redundant — DXVK cannot select a path the device does not offer. It is worth
confirming whether it is still required, because if it is, that implies the
extension is partially advertised somewhere in the chain and the real behaviour
is more complicated than the capability dump suggests.
