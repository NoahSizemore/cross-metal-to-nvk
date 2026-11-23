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

**Impact:** the largest known fixable performance item.

```
unsupported pte_kind(0xb/0xc)
nvk-compress: compressed alloc N refused (-13), falling back uncompressed
```

This fires on every render target, meaning the GPU runs with all memory
compression disabled. On a card whose bandwidth budget assumes compression,
this is a broad, constant tax rather than a per-feature one.

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
Lowering output resolution reduces it proportionally.

---

## Reporting these upstream

Include `bin/nvk-doctor` output, which captures driver version, runtime build
ID, ICD enumeration and recent refusals. Quote the driver's own diagnostic text
verbatim — it is precise, and paraphrasing it loses the detail that makes each
of these actionable.
