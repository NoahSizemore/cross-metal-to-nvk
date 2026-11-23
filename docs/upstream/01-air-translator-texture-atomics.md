# The AIR translator rejects `air.atomic_fetch_add_explicit_texture_2d`

**Component:** NVMTL AIR translator
**Severity:** correctness — a valid shader is refused, so the feature using it
cannot run on the Metal translation path
**Affects:** any D3D11 title using FSR2 (FidelityFX Super Resolution 2)

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

Running a D3D11 game with FSR2 enabled on the Metal translation path, the
translator refuses one shader and writes it to
`/Library/GPUBundles/nvmtl/failed-air/main0-<hash>.ll`. Its first line:

```
; translator refusal (kernel): air.atomic_fetch_add_explicit_texture_2d.u.v4i32
  value must be a four-lane i32 vector
```

The shader is FSR2's Compute Luminance Pyramid (FidelityFX SPD), identifiable
in the dump by `cbFSR2_t`, `spdIntermediateA/B/G/R` and
`rw_spd_global_atomic`. The refusal covers two instructions in a 2,445-line
module.

## Why this looks like a translator bug

The AIR module was emitted by Apple's own Metal compiler, so it is valid AIR by
construction. The translator is applying a stricter rule than the producer
does: it requires a four-lane `i32` vector for the atomic's value operand
where the emitted code supplies something else that Metal itself accepts.

## Expected behaviour

Accept the operand form Apple's compiler emits. If some forms genuinely cannot
be lowered, the refusal should name the instruction's actual operand types
alongside the expected ones, so the gap is visible without reading the dump.

## A second, smaller issue in the same area

The diagnostic is invisible by default. `/Library/GPUBundles/` is root-owned
and `failed-air/` does not exist after installation. The driver probes
writability (it creates `.probe-<pid>`), finds it cannot write, and discards
the dump silently. The driver's single best diagnostic is therefore switched
off for every user until they do this by hand:

```sh
sudo mkdir -p /Library/GPUBundles/nvmtl/failed-air
sudo chown "$(id -un)":staff /Library/GPUBundles/nvmtl/failed-air
```

Creating the directory at install time, with an owner who can write to it,
would make every future report of this kind actionable.

## Notes

This does **not** affect the native NVK path — there is no AIR translation
there, and FSR2 works. It was found while comparing the two paths.
