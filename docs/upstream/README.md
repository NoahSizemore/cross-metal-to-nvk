# Upstream reports

Six findings about the driver and its NVK runtime, written as reports that
can be submitted as they stand. They are **not** bugs in this repository's
scripts, and none of them is fixable here.

Each report is self-contained: environment, what was observed, the driver's own
diagnostic quoted verbatim, why it is a driver issue, and what the honest
behaviour would be. [../DRIVER-ISSUES.md](../DRIVER-ISSUES.md) is the same
material written for someone debugging their own machine; these are written for
whoever maintains the driver.

| Report | Severity | Subject |
|---|---|---|
| [01-air-translator-texture-atomics.md](01-air-translator-texture-atomics.md) | correctness | the AIR translator rejects a valid Apple-emitted shader |
| [02-srgb-storage-image-silent-loss.md](02-srgb-storage-image-silent-loss.md) | silent data loss | sRGB storage images accept writes and discard them |
| [03-framebuffer-compression-refused.md](03-framebuffer-compression-refused.md) | performance | compression refused on every render target |
| [04-native-vulkan-swapchain-creation-fails.md](04-native-vulkan-swapchain-creation-fails.md) | blocking + conformance | a game-driven `vkCreateSwapchainKHR` fails, returning a non-spec `VkResult` |
| [05-descriptor-buffer-unavailable.md](05-descriptor-buffer-unavailable.md) | performance | `VK_EXT_descriptor_buffer` unavailable, forcing DXVK's legacy binding model |
| [06-immediate-present-mode-not-honoured.md](06-immediate-present-mode-not-honoured.md) | conformance | `IMMEDIATE` present mode granted, then presentation latches to vblank anyway |

Report 06 is the best-evidenced of the six — the driver's own sysctl
description ("tearing stays off") states that the flip path cannot implement the
mode it reports as active. It is a conformance report: an earlier draft also
blamed it for the frame pacing on the reference machine, and per-frame
inspection did not support that, so the claim was withdrawn rather than left in
weakened form.

Reports 04 and 05 are narrower than the first three. 04 concerns a
configuration the runtime's README does not claim to support, and is filed for
the conformance half of it as much as the failure. 05 is written as a question
about whether a capability gap is deliberate, not as an assertion that it is a
bug.

**These have not been submitted.** Submitting them is a decision for whoever
owns this repository, and the venue depends on where the driver's author takes
reports. Before sending any of them, re-run `bin/nvk-doctor` and replace the
environment block — the versions below were read from one machine on one day,
and the runtime has already changed underneath this documentation once.

Quote the driver's diagnostic text exactly. It is precise, and paraphrasing
loses the detail that makes each of these actionable.
