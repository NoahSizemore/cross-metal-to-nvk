# Native Windows Vulkan swapchain creation fails, and returns a non-spec VkResult

**Component:** Wine Vulkan bridge / NVK WSI (`vkCreateSwapchainKHR`)
**Severity:** blocking for Windows games that use the Vulkan API directly;
plus a spec conformance defect that makes the failure undiagnosable
**Affects:** any Windows game driving `VK_KHR_swapchain` itself, rather than
reaching Vulkan through DXVK or vkd3d

> **Scope note, stated up front.** The runtime's own README requires "an **x64
> Windows D3D11 or D3D12** game", so a Windows game calling Vulkan natively is
> outside what has been qualified. This is therefore a report about an
> unsupported configuration, filed because the failure mode is specific, fully
> reproducible, and because the second defect below is a conformance issue that
> holds regardless of whether the first is ever supported.

## Environment

```
GPU            NVIDIA GeForce RTX 4070 (AD104, 10de:2786)
CPU / platform Intel i7-13700K, Hackintosh (OpenCore)
OS             macOS 26.7.3 (25G342), x86_64
Driver bundle  NVMTLDriver.bundle 2.9, /Library/GPUBundles/nvmtl/
Vulkan loader  libvulkan.1.4.362.dylib
NVK reports    device "NVIDIA GeForce RTX 4070 (NVK AD104-A)", NVK 26.3.1
               driver version as seen by the game: 26.0.192.1
Wine runtime   nvk-wine-provider-63e41c4c0cb0 (binary),
               nvk-wine-provider-66fb06568adc (BUILD.json source_runtime_id)
CrossOver      26.3.0.39832
Boot-args      no -nvrmnopm (power management not disabled)
```

> Captured with `nvk-doctor` from
> <https://github.com/>…/cross-metal-to-nvk. Note that the runtime binary and
> its own `BUILD.json` report different identifiers; both are included because
> it is not clear which one you want.

## What happens

Two Source 2 games, launched with `-vulkan` so the engine uses its own Vulkan
renderer instead of D3D11, both fail at the same call. Recovered from the
games' own crash reports (`CommentStreamA` in the minidump), console history
in original order:

```
Creating render device for graphics adapter 0 'NVIDIA GeForce RTX 4070 (NVK AD104-A)'
    [VendorId 0x10DE / DeviceId 0x2786]: 26.0.192.1
Vulkan Physical Device: NVIDIA GeForce RTX 4070 (NVK AD104-A)
ERROR! VK call failed! result = Unknown VkResult value
    ( vkCreateSwapchainKHR( pDeviceVulkan, &swapChainCreateInfo, nullptr, &m_pSwapChainKHR ) )
Call to vkCreateSwapchainWSI returned a error Unknown VkResult value.
Failed to initialize video!
Reset video config to desktop mode 2560x1440!
FATAL ERROR: AppSystemDict: Error in Init() of interface 'RenderDeviceMgr001'!
```

The process then aborts through the engine's fatal-error path, which surfaces
as exception `0x80000003` (`BREAKPOINT`) raised inside `kernelbase.dll` — a
deliberate abort, not a memory fault. Because the error dialog cannot be
displayed, the user-visible symptom is a dock icon appearing and the process
exiting with status 1 having drawn nothing.

Reproduced identically on:

| Game | appid | Build | Uptime at failure |
|---|---|---|---|
| Counter-Strike 2 | 730 | 10955 (rev 11268945) | 11.19 s |
| Deadlock | 1422450 | — | 5.48 s |

## The two distinct defects

### 1. `vkCreateSwapchainKHR` fails where DXVK's swapchain succeeds

Everything before presentation setup works. Instance creation, physical device
enumeration and logical device creation all succeed, and the device is
correctly identified with its real vendor ID (`0x10de`) — this is native NVK,
not a translation layer. `rendersystemvulkan.dll` loads, and the Vulkan shader
archives (`shaders_vulkan_000.vpk`, `shaders_vulkan_dir.vpk`) are present in
the depot. The failure is isolated to one call.

The same machine runs the same two games through DXVK 3.1.1+nvk without
trouble, and DXVK creates a swapchain on the same bridge. So the WSI path is
not broadly broken; something about what the game requests is refused where
what DXVK requests is not.

The engine reports its surface state as unavailable at the point of failure:

```
Vid: Unavailable, render at 0 x 0, display at 0 x 0, refresh rate 0.00Hz (0Hz desktop)
refreshrate_numerator:0, refreshrate_denominator:0, fullscreen:0, nowindowborder:1
```

This may be a symptom of the failed initialisation rather than its cause — the
line is printed after `g_pEngineServiceMgr` has already gone NULL — so it is
offered as context, not as a diagnosis. Forcing an explicit non-zero extent
with `-w 1920 -h 1080` does **not** change the outcome; the failure is
identical.

### 2. The returned `VkResult` is not a value in the enum

`Unknown VkResult value` is the engine's fallback when its result-to-string
mapping does not recognise the code it was handed. That mapping covers the
core codes and the `VK_KHR_swapchain` ones, including `VK_ERROR_SURFACE_LOST_KHR`
and `VK_ERROR_NATIVE_WINDOW_IN_USE_KHR`. The value returned here is therefore
outside the set `vkCreateSwapchainKHR` is specified to return.

This is a conformance defect independent of defect 1. Any correct refusal —
`VK_ERROR_INITIALIZATION_FAILED`, `VK_ERROR_SURFACE_LOST_KHR`,
`VK_ERROR_OUT_OF_DEVICE_MEMORY` — would have been reported by name and would
have made this diagnosable from outside the driver. Returning an unmapped
value turns a clear refusal into a dead end.

## What was ruled out

* **Not the launch flag.** `-vulkan` took effect: `Render system: Vulkan`, and
  `rendersystemvulkan.dll` is in the loaded module list.
* **Not a missing renderer or missing shaders.** Both ship in the Windows
  depots for both games.
* **Not a missing Vulkan loader in the prefix.** `vulkan-1.dll` and
  `winevulkan.dll` are both present and both appear in the loaded module list.
* **Not a zero extent from the game's own configuration.** Forcing
  `-w 1920 -h 1080` reproduces the failure unchanged.
* **Not the engine's Vulkan backend being broken in general.** The same
  renderer is the default on Linux.
* **Not power management.** `-nvrmnopm` is not set.

## Capabilities that may be relevant

Read from the same device by DXVK on the same machine. Several swapchain-adjacent
extensions are unavailable, and a game driving WSI itself is far more likely
than DXVK to depend on one:

```
VK_KHR_swapchain_mutable_format   khrSwapchainMutableFormat : 0
VK_KHR_swapchain_maintenance1     swapchainMaintenance1     : 0
VK_EXT_swapchain_maintenance1     swapchainMaintenance1     : 0
VK_EXT_full_screen_exclusive      extFullScreenExclusive    : 0
VK_EXT_swapchain_colorspace       extSwapchainColorSpace    : 0
VK_KHR_incremental_present        khrIncrementalPresent     : 0
VK_KHR_present_id / present_wait  presentId / presentWait   : 0 / 0
```

If `vkCreateSwapchainKHR` refuses a `VkSwapchainCreateInfoKHR` whose
`imageUsage`, `imageFormat` or flags fall outside a supported subset, saying so
through the specified error code would identify which field is at fault.

## What would help

1. Which `VkResult` the bridge actually returns from `vkCreateSwapchainKHR` in
   this case, and whether that value originates in winevulkan, in the NVK WSI
   implementation, or in the Metal presentation bridge beneath it.
2. Mapping that return onto a value `vkCreateSwapchainKHR` is specified to
   return. This alone would make the configuration diagnosable by anyone
   hitting it, independently of whether it is ever supported.
3. Whether a `VkSwapchainCreateInfoKHR` field is being rejected, and if so
   which — the natural candidates being `imageUsage` bits beyond
   `COLOR_ATTACHMENT`, a non-`UNORM` or sRGB `imageFormat`, a `presentMode`
   other than `FIFO`, or `VK_SWAPCHAIN_CREATE_MUTABLE_FORMAT_BIT_KHR` given
   that `VK_KHR_swapchain_mutable_format` is unavailable.
4. Whether supporting a game-driven swapchain is in scope at all. If it is not,
   a documented statement to that effect is a complete answer to defect 1, and
   defect 2 still stands on its own.

## Reproducing

```sh
# Either game, launched directly with the native Vulkan renderer.
./bin/nvk-mkapp --bottle Steam \
  --app 'C:\Program Files (x86)\Steam\steamapps\common\Deadlock\game\bin\win64\deadlock.exe' \
  --name 'Deadlock (Vulkan test)' --args '-vulkan'
```

The engine's own report is the useful artefact, and it is not written to
`console.log` — the process dies before console logging flushes. It is embedded
in the minidump the game drops beside its executable:

```
<game>/game/bin/win64/<name>_<date>_<time>_0_error.mdmp
```

Read it with `bin/nvk-mdmp`, which extracts the exception record, the loaded
graphics modules and the engine's fatal-error report without needing a
Windows debugger.
