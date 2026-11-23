# sRGB textures accept `ShaderWrite` and then discard the writes

**Component:** NVK / Metal texture creation
**Severity:** silent data loss — wrong output with no error returned to the
application
**Affects:** anything binding an sRGB render target as a storage image

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

The driver logs this, then continues:

```
newTextureWithDescriptor: pixel format 71/81 asked for ShaderWrite and NVK
cannot make it a storage image — shader writes to it will be LOST
```

Format 71 is `MTLPixelFormatRGBA8Unorm_sRGB`; 81 is
`MTLPixelFormatBGRA8Unorm_sRGB`. Texture creation succeeds. The application
receives a valid texture, writes to it, and the writes do not land. The
observable result is black or frozen frames, with nothing in the log unless you
already know to grep for this line.

## Root cause

Vulkan defines no `STORAGE_IMAGE` feature bit for sRGB formats; Metal permits
the usage. The driver bridges the two and resolves the mismatch by accepting
the request and dropping the writes.

## Expected behaviour

Either of these is defensible; the current behaviour is not:

1. **Refuse the creation.** Return failure for `ShaderWrite` on an sRGB
   format, so the caller can fall back. This matches what Vulkan promises.
2. **Write through a linear view.** Create the texture with the matching
   non-sRGB format for the storage view, keeping the sRGB view for sampling.
   This matches what the caller intended.

The one behaviour that cannot be right is succeeding and discarding, because
there is no way for the application to detect it.

## Why this is worth fixing above its apparent frequency

The failure is invisible at the API boundary. A developer hitting it sees a
black frame and will look at their own shader, their own barriers, and their
own format selection — the driver has already told them the answer, in a log
line they have no reason to be reading.
