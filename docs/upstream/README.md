# Upstream reports

Three findings about the driver and its NVK runtime, written as reports that
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

**These have not been submitted.** Submitting them is a decision for whoever
owns this repository, and the venue depends on where the driver's author takes
reports. Before sending any of them, re-run `bin/nvk-doctor` and replace the
environment block — the versions below were read from one machine on one day,
and the runtime has already changed underneath this documentation once.

Quote the driver's diagnostic text exactly. It is precise, and paraphrasing
loses the detail that makes each of these actionable.
