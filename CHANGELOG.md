# Changelog

Notable changes, and — more usefully — what was measured and what was ruled
out. Findings are recorded here rather than in the README, which stays a
getting-started document.

Dates are when the observation was made on the reference machine (RTX 4070,
i7-13700K Hackintosh, macOS 26, CrossOver 26.3). Everything below is one
configuration unless stated otherwise.

---

## Unreleased

### Added

* `nvk-bottle setup --env KEY=VALUE` (repeatable) — puts an arbitrary variable
  in the managed block, which is how the driver's own tuning knobs get tested.
  Values containing a quote or backslash are refused, since they are written
  into `cxbottle.conf` inside double quotes. Extra vars live *inside* the
  sentinel block, so a re-run replaces them wholesale and they never need to
  join `OWNED_KEYS`.
* `nvk-bottle setup --hud LIST` and `--log-level LEVEL` — the defaults
  (`devinfo,fps,frametimes` at log level `info`) are right for diagnosing and
  wrong for measuring. `--hud fps --log-level none` is the measuring pair.

### RESOLVED: env delivery works. The gap was process coverage.

`NVRM_ONE_CONN_PER_MAP=1`, delivered through `CX_ENV`, was **read and acted
upon** — the driver's message text changes, not just its echo:

```
18: nvrm_xnu: one connection per CPU mapping (NVRM_ONE_CONN_PER_MAP=1, kext token maps not asked or refused)
19: nvrm_xnu: CPU mappings share hub connections (NVRM_ONE_CONN_PER_MAP=unset, kext token maps yes)
```

Two device opens in one session: one has the variable, one does not. The second
is a Steam-side process. `profiles/steam.conf` carried no `env` field, so the
**Steam (NVK)** launcher set no `CX_ENV`, and nothing in Steam's process tree
received it — while Deadlock requires Steam to be running, so that tree is
always present.

That is the whole explanation for the earlier null results, and it means the
environment must be set on **every** launcher for the bottle, not just the
game's. Both profiles now carry `env`.

### A patched CrossOver `wine` broke every launch after a reboot

Exit status 134 (`SIGABRT`) on every app in the bottle, Steam included:

```
dyld: terminating because inserted dylib '/tmp/hook.dylib' could not be loaded
```

CrossOver's own `wine` — a Perl script — had been modified to set
`DYLD_INSERT_LIBRARIES=/tmp/hook.dylib` on every `wineloader` launch. `/tmp` is
wiped on reboot, so it worked until the first restart and then aborted
everything before Wine started. Its modification date differed from every
sibling binary in that directory, and it had lost the extended attributes the
siblings still carry.

Not part of the NullMoth driver integration (its scripts never reference
`hook.dylib`), so commenting the injection out is safe and does not affect NVK.
Written up in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) because nothing
in this project's own logs explains it — `dyld` aborts before any of our
instrumentation runs.

### Remaining DXVK options, enumerated and narrowed

The options this build actually supports were read from the shipped `d3d11.dll`
rather than from memory:

```sh
strings -a "<bottle>/drive_c/windows/system32/d3d11.dll" \
  | grep -E '^(dxvk|d3d11|dxgi)\.[a-zA-Z]+$' | sort -u
```

Several candidates are eliminated by evidence from the same logs:

| Option | Why it is not applicable |
|---|---|
| `dxvk.enableGraphicsPipelineLibrary` | **already in use** — DXVK logs "Graphics pipeline libraries supported", so pipeline-library compilation is active and forcing it is a no-op |
| `d3d11.maxTessFactor` | **no tessellation** — shader-stage census over a debug session: 2366 `vs`, 1854 `cs`, 12 `gs`, and zero `hs`/`ds` |
| `d3d11.disableMsaa` | **no MSAA** — no sample-count or resolve activity; antialiasing is handled by FSR2 |
| `dxvk.enableDescriptorBuffer` / `enableDescriptorHeap` | both extensions unavailable on the device |

That shader census is independently useful: **this workload is compute-heavy**,
with nearly as many compute shaders as vertex shaders. Barrier and
synchronisation overhead between dispatches is therefore a plausible share of
GPU time in the heavy regime, which makes `d3d11.relaxedGraphicsBarriers` the
best-fitting untested option rather than a generic guess.

Candidates that survive, with mechanism:

1. **`d3d11.relaxedGraphicsBarriers = True`** (and `d3d11.relaxedBarriers`) —
   fewer barriers, less GPU stalling between dispatches, on a workload measured
   as compute-heavy and GPU-bound in dense geometry. **Correctness risk**: this
   driver already has two documented silent-corruption bugs, so validate
   visually rather than trusting frame times.
2. **`dxgi.maxFrameLatency = 3`** — a deeper frame queue absorbs spikes. This
   reduces *perceived* stutter without reducing its cause, and it costs input
   latency, which matters in a shooter. A trade, not a win.
3. **`dxvk.maxMemoryBudget`** — sessions show 688 VRAM grants and 2.91 GiB
   granted and released, i.e. heavy residency churn. A larger budget means fewer
   evictions and re-uploads, and re-upload is a plausible cause of the
   transition spike. The default is unknown, so this has to be measured rather
   than predicted.
4. **`r_texture_stream_mip_bias 0`** (currently `1`) — a Source 2 setting, not
   DXVK. Less aggressive streaming keeps more resident up front, trading VRAM
   (12 GiB card, ~9 GiB budget) for fewer mid-session uploads. Targets the
   transition spike at its source.
5. `dxvk.numCompilerThreads = 24` (24 logical cores) and
   `dxvk.trackPipelineLifetime` — low expected value, since pipeline libraries
   are already active.

### CORRECTION: power management *was* disabled, and `tgp` fixes it

An earlier entry closed the power and clock hypothesis on the grounds that the
GPU boost daemon was installed and running (`gpuboost=1`, pid alive). **That was
wrong.** The boost daemon holds a "boost to maximum" *request*, and TGP, GPS and
NVPCF — the framework that request acts through — were all switched off, because
the `tgp` experimental feature was not enabled. The request had nothing to act
on.

Enabling it (`--experimental tgp`, adding boot-args
`nvrmtgp=1 nvrmgps=1 nvrmnvpcf=1`, reboot required) produced the clearest result
of the whole effort. Measured with `tile` also on, so the two are not fully
separated:

| | `tile` only | `tile` + `tgp` |
|---|---|---|
| mean frame time, light area | 4.2 ms | **3.8 ms** |
| `gpuload`, light area | 82–95% | **65–80%** |
| high-geometry fps | baseline | **+3–5 fps, very steady** |

**Lower GPU utilisation together with lower frame time is the signature of the
GPU getting faster, not of less work.** The same frame costs less GPU time, so
utilisation falls while throughput rises — which is what enabling real power and
clock management looks like. The high-geometry figures becoming "very consistent
and steady" fits the same explanation.

So the performance gap always had a power-management component, and every
measurement in this document before this point was taken on a GPU whose power
framework was disabled. The caveat is that `tgp` was never tested alone, only
alongside `tile`.

### CLOSED: the power readback is unavailable on this hardware, by design

`NVRM_610_MAXPOWER_MW=200000` was retried with `nvrmgps=1` active and produced
no `GPS max power` line anywhere — not in the launcher logs, not in the bottle's
DXVK logs, not in the unified system log.

The mechanism is in the kext's own strings:

```
NVRM: Unable to retrieve 3x NVPCF supported functions. Possibly not supported by SBIOS rc = %x
NVRM: Unable to retrieve DC System power limits table data. Possibly not supported by SBIOS.
cliresCtrlCmdSystemNVPCFGetPowerModeInfo_IMPL
```

**NVPCF negotiates power limits through ACPI DSM methods supplied by the system
firmware** — it is an OEM laptop and prebuilt feature (Dynamic Boost). A desktop
Hackintosh running OpenCore does not provide those methods, so the GPS path
cannot engage and there is no power limit to read or set through it.

So the power limit is **not** readable or settable on this class of machine, and
the absence of a log line is the expected outcome rather than a delivery
failure. This closes the question properly, with a mechanism — unlike the
earlier closure, which reasoned only that the boost daemon was running.

Note this does not undermine `tgp`: it measurably helped. Enabling `nvrmtgp=1`
evidently improves clock or power governance through paths that do not depend on
platform firmware, even though the NVPCF negotiation on top of it cannot work
here. Keep `tgp` on; stop pursuing the readback.

### Experimental features: the full measured matrix

Stationary paired comparisons. Light-area figures are mean frame time at a fixed
spot; heavy-area figures are fps in dense geometry.

**`gameprio` was on for every test after its own**, so each row below is
cumulative rather than an isolated feature:

| Configuration | Light area | Heavy area | `gpuload` (light) |
|---|---|---|---|
| none (baseline) | 4.4 ms, spikes 41 ms | — | 50–80% |
| `gameprio` | **3.2 ms**, spikes 10–15 ms | *not measured* | 70–90% |
| `gameprio,tile` | 4.2 ms | +1 fps | 82–95% |
| `gameprio,tgp` | 5.0 ms | 39–41 fps | higher |
| `gameprio,tile,tgp` | 3.8 ms | **40–43 fps, very steady** | 65–80% |
| `gameprio,tile,tgp,icb` | 5.0 ms | 38–40 fps | 95–100% (97 avg) |
| `tile,tgp` (no `gameprio`) | same as above | 39–40 fps | — |

The last row isolates `gameprio`'s contribution on top of the other two: **+1–3
fps in heavy geometry at no light-area cost.** Combined with its spike result
against the bare baseline, it is worth keeping in every configuration.

**`gameprio` is the unambiguous win**: 4.4 → 3.2 ms and spikes 41 → 10–15 ms,
measured against a known-off baseline.

**Adding `tile` or `tgp` costs light-area frame time.** Against `gameprio`
alone's 3.2 ms: `tile` gives 4.2 ms, `tgp` 5.0 ms, both together 3.8 ms. Every
combination is *worse* in the light area than `gameprio` by itself. They were
kept because the heavy area improved — 40–43 fps, very steady, against a
baseline around 37–38.

**That trade is not actually established, because the comparison was never
run.** Heavy-area frame rate with `gameprio` alone was never measured. So the
question of whether `tile` and `tgp` earn their light-area cost is open:

* If `gameprio` alone also gives ~40 fps in heavy geometry, then `tile` and
  `tgp` are net negative and should come off.
* If `gameprio` alone gives ~37–38 there, the trade is real and the three-way
  set is correct.

**The missing measurement is heavy-area fps with `--experimental gameprio`.**
That single run decides the recommended configuration.

One further reading. **High GPU utilisation is not the goal, and an earlier
entry here implied it was.** Adding `icb` drove `gpuload` to 95–100% while making
*both* axes worse. A busier GPU doing less useful work is added overhead.
Utilisation is only interpretable next to frame time: `gameprio` raising it
alongside a 27% frame-time improvement was meaningful; `icb` raising it alongside
a regression is the opposite.

`icb` is therefore confirmed harmful, not merely neutral. GPU indirect command
buffers were the best *theoretical* fit for a per-draw-bound workload — which is
exactly why the negative result is worth recording rather than quietly dropping.

Session measurement on that set, for the record — 278 s of normal play:

```
mean flip rate         77.3 /s
mean time in flip      3.476 ms   (26.9% of wall clock)
vram grants            688  (2.91 GiB)   145,417 B per flip
```

77.3 presented frames/s sits in the upper part of the 61.6–82.9 range recorded
across earlier configurations, and **that is not evidence of improvement** —
whole-session gameplay numbers carry a 35% spread, which is wider than any
effect measured here. The evidence for these three features is the stationary
paired comparisons; this figure is a baseline for the recommended set, not a
result.

### CONFIRMED WIN: `--experimental gameprio` (`NVMTL_GAME_GPU_PRIORITY=1`)

Stationary paired comparison, identical spot and view, light-geometry area:

| | `gameprio` off | `gameprio` on | Change |
|---|---|---|---|
| mean frame time | 4.4 ms | **3.2 ms** | −27% |
| frame-time spikes | **41 ms** | **10–15 ms** | roughly −70% |
| `gpuload` | 50–80% | **70–90%** | GPU better fed |

The `gpuload` rise is the mechanism confirming itself: the complaint in this
regime was that the GPU could not be given work fast enough, and raising the
game's GPU priority demonstrably feeds it better. Mean frame time improving is
welcome; **the spike collapse from 41 ms to 10–15 ms is the result that
matters**, because frame-time outliers were the actual subjective problem
throughout this document, not average throughput.

This is also the first measurement all day large enough to trust, and it is
trustworthy because of the method rather than the size: a stationary paired
comparison on identical geometry removes the scene variance that made every
3-minute gameplay A/B worthless (35% spread between identical configurations).

**Keep it on.** Enabled with:

```sh
sudo /Library/NullMoth/nullmoth-setup.sh --experimental gameprio
```

Note the conf-pickup log line (`nvk: KEY=VALUE (nvrm610.conf)`) never appeared,
so that logging is evidently gated or limited to certain value types. The effect
is measurable regardless, which is better evidence than a log line — do not
treat the missing line as the feature being inactive.

It also establishes that the **`NVMTL_*` family delivered through
`nvrm610.conf` is live**, in contrast to the inert `NVK_CMDMEM_*` variables.
That makes the two remaining `NVMTL_*` experimental features the best untested
candidates, and one of them is squarely aimed at this stack's central problem:

* **`icb` → `NVMTL_GPU_ICB=1`** — GPU indirect command buffers. Letting the GPU
  build its own command lists attacks per-draw submission cost directly, which
  is the central finding of this document.
* **`tile` → `NVMTL_TILE_SHADING=1`** — tiled shading, a bandwidth measure.

### The driver has an official tuning surface, and most of it is off by default

`/Library/NullMoth/nullmoth-setup.sh` is the driver's own configuration tool.
None of this is mentioned in the driver README or anywhere in this repository,
and it is where the knobs actually live. Found while chasing why
`NVRM_610_MAXPOWER_MW` produced no log line.

Relevant options: `--gpu-boost on|off|remove`, `--game-mode on|off|status`,
`--experimental <comma-separated ids>`, `--knob KEY=VALUE`, and `--dry` for a
no-op preview.

State on the reference machine:

| Feature | State |
|---|---|
| GPU boost daemon (`nvmtl-boost`) | **on** — `gpuboost=1`, running as pid 401 |
| Game Mode (raises the foreground game, demotes background) | **on** — policy daemon and indicator running |
| every experimental feature | **off** |

GPU boost holds a "boost to maximum" resource-manager request, so **the power
and clock hypothesis is closed**: boost was already enabled and held throughout
every measurement in this document. Game Mode was likewise already on.

The experimental features are the part that is off, and two of them bear
directly on the findings here:

```
tgp)      -> boot-args  nvrmtgp=1 nvrmgps=1 nvrmnvpcf=1
gameprio) -> NVMTL_GAME_GPU_PRIORITY=1   (written into nvrm610.conf)
```

**`tgp` explains the missing power readback.** `nvrmgps=1` enables the GPS
subsystem — the one that emits `nvrm: GPS max power ... reads back ... mW` — and
it is not in this machine's boot-args. So `NVRM_610_MAXPOWER_MW` had nothing to
talk to, which is why no line ever appeared regardless of how it was delivered.
TGP and NVPCF are the power-management framework alongside it.

**`gameprio` targets the measured submission-bound regime** — a GPU priority for
games, where light scenes cap at ~110 fps with the GPU only 50–60% busy.

The remaining ids are `hwrt` (`NVK_HWRT_QUERY=1`), `curves` (`NVK_CURVES=1`),
`tile` (`NVMTL_TILE_SHADING=1`), `icb` (`NVMTL_GPU_ICB=1`), plus hardware ones
not relevant here (`kbl`, `kblhid`, `igpuproxy`, `xvt`, `hybrid20`, `rtd3`,
`aspm`, `hda`).

Two mechanics worth knowing. `--experimental` takes the **whole** desired list,
not a delta, and `none` clears it; the script records what it enabled in its own
state file so turning a feature off removes exactly what it added and never a
boot argument the user set. And the knob-file features are written into
`/Library/GPUBundles/nvmtl/nvrm610.conf`, which `libvulkan_nouveau.dylib` reads
**per process** — it logs `nvk: KEY=VALUE (nvrm610.conf)` when it picks one up,
so those are self-verifying and need no reboot. Boot-argument features do need
one.

The script describes these as "written and tested offline but not yet measured
on hardware", so they are genuinely unmeasured rather than merely undocumented.

### RESOLVED: `NVRM_*` variables are live; `NVK_CMDMEM_*` are inert

Settled by running both probes:

| Variable | Set where | Result |
|---|---|---|
| `NVRM_ONE_CONN_PER_MAP=1` | game launcher | **honoured** — message text changed to "one connection per CPU mapping" |
| `NVK_CMDMEM_SLAB_KB=2048` | **both** launchers | ignored; every process still logged `=1024` |

Delivery is therefore not the problem — the same channel carries one variable
and not the other. The `NVK_CMDMEM_*` family is **inert in this build**: the
runtime prints those values but does not take them from the environment, so the
log line is reporting compiled-in defaults. Most likely the slab allocator was
reworked and its diagnostic was left behind.

This is consistent with the one knob that *did* visibly do something:
`NVK_DESC_QUARANTINE=0` caused a large regression and quality loss. It is not in
the `CMDMEM` family, so it was never expected to be inert. That observation
stops being anomalous.

**So the tuning surface is open, with one dead family in it.** Do not spend
further effort on `NVK_CMDMEM_RECYCLE`, `NVK_CMDMEM_SLAB_KB`,
`NVK_CMDMEM_LIVE_MAX` or their siblings. The `NVRM_*` knobs are worth testing,
and `NVRM_610_MAXPOWER_MW` is first — the GPU power limit has never actually run,
and the driver logs a hardware readback when it is set:

```
nvrm: GPS max power %lu mW set rc 0x%x, reads back %u mW (rc 0x%x)
```

Other live candidates in that namespace: `NVRM_TSG_TIMESLICE_US` and
`NVRM_TSG_Q0_HIGH` (GPU scheduling), `NVRM_ASYNC`, `NVRM_FLUSH_TIMEOUT_MS`,
`NVRM_EVENT_WAIT`, `NVRM_XNU_NO_WC` (write-combining on CPU mappings) and
`NVRM_XNU_HUBS`.

Set the variable on **every** launcher for the bottle. `NVRM_ONE_CONN_PER_MAP`
appeared as `=1` on one device open and `unset` on another in the same session,
which is what partial coverage looks like.

### Superseded: `NVK_*` knobs do not take effect, cause unknown

`NVK_CMDMEM_RECYCLE=1` has now been delivered by three routes, and the runtime
logs `recycler off (NVK_CMDMEM_RECYCLE=0, NVK_CMDMEM_LIVE_MAX=512)` every time —
including on four separate NVK initialisations within a single session where the
launcher started Steam itself, so the whole process tree descended from it.

Routes tried:

1. `cxbottle.conf [EnvironmentVariables]`
2. a plain `export` in the generated launcher
3. `CX_ENV`, which CrossOver's `wine` reads and splits into `%ENV`

**An earlier revision of this entry claimed routes 1 and 2 fail because they
cannot reach native code, and that `CX_ENV` was the fix. That reasoning was
wrong and is withdrawn.** Reading CrossOver's `wine` — it is a Perl script —
shows no environment pruning anywhere:

```perl
CXBottle::set_environment($cxconfig, "...");          # line 653, cxbottle.conf
read_env_from_string($opt_env) if (defined $opt_env); # line 722, CX_ENV
exec $cmd, @wine_args, @args;                         # line 1249
```

Everything lands in `%ENV` and `exec` passes `%ENV` wholesale, so cxbottle.conf
variables *do* reach the Unix environment that native dylibs read. The
`dump_wine_environment` function that looked like a filter is only a diagnostic
printer with a fixed list of names.

Worse for the original claim: `"NVK_CMDMEM_RECYCLE" = "1"` was still present at
line 329 of `cxbottle.conf` throughout, so the variable was in the game's
environment by route 1 even while routes 2 and 3 were being blamed.

So delivery is **not** demonstrated to be the problem. Two live hypotheses:

* **The driver reads the variable and declines to act on it** — the log prints an
  *effective* value, so a recycler compiled out or gated behind another
  condition would still print `=0`.
* **The driver does not read its environment in this context** at all.

`NVK_CMDMEM_SLAB_KB=2048` was then delivered through `CX_ENV` and the runtime
still logged `NVK_CMDMEM_SLAB_KB=1024`. So a plain numeric with no plausible
gating also fails to arrive, which makes "the driver reads it and declines"
much less likely than "the driver is not reading its environment here".

That is still not proof, because a default value gets printed whether or not
the variable was read. The driver does, however, echo one variable in a form
that distinguishes the two cases:

```
nvrm_xnu: CPU mappings share hub connections (NVRM_ONE_CONN_PER_MAP=unset, kext token maps yes)
```

`unset` is a positive statement that `getenv` returned NULL. Setting
`NVRM_ONE_CONN_PER_MAP=1` therefore settles it: if the log still reads `unset`,
the driver is definitively not reading the process environment; if it reads
`=1`, the environment is read and the `NVK_CMDMEM_*` knobs are inert for their
own reasons. This probe should have been chosen first — both earlier ones
report defaults, which cannot distinguish "read" from "not read".

### Deadlock cannot be launched with Steam closed

It crashes on boot unless Steam is already running, even though
`needs_steam=yes` starts Steam and waits for both a `wineserver` on this prefix
and a `steamwebhelper`. The two-app split is **required** for this title, not
merely preferred.

This also constrains diagnostics: any procedure calling for "Steam fully
closed" cannot be run on Deadlock, which invalidates the control condition
assumed in the env-delivery tests above. Measured both ways where possible, with
identical results.

`nvk-mkapp --env` now routes through `CX_ENV` regardless. That is CrossOver's
documented mechanism for exactly this purpose ("for instance to control VKD3D
debug log messages"), so it is the right channel even though it was not the
fix it was presented as.

**Consequence for earlier results:** all `NVK_*` findings remain void rather
than negative, but for an unknown reason rather than the one previously
recorded. `NVRM_610_MAXPOWER_MW` producing no log line is similarly
unexplained. `NVK_DESC_QUARANTINE=0` producing a large regression and visible
quality loss is the one case where *something* clearly took effect, which sits
awkwardly with every other knob appearing inert — treat it as unexplained.

### Found: the driver has a large undocumented tuning surface

Neither the driver README nor this repository mentioned any of it. Listed with:

```sh
strings -a /Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib \
  | grep -E '^(NVK|NVRM)_[A-Z0-9_]+$' | sort -u
for f in /Library/GPUBundles/nvmtl/wine/lib/*.dylib; do
  strings -a "$f" | grep -E '^WINE_NVK_[A-Z0-9_]+$'
done | sort -u
```

Of interest for a bandwidth- and draw-bound workload: `NVK_CMDMEM_RECYCLE`
(the runtime logs it as **off** by default), `NVK_DESC_QUARANTINE`,
`NVK_CMDPOOL_GPU_UNCACHED`, `NVK_SYSMEM_GPU_UNCACHED`, `NVK_QUEUE_COUNT`,
`NVK_L2_TAIL`, `NVK_BAR_VRAM`, `NVK_NO_BIGPAGE`, `NVK_EXPERIMENTAL`,
`NVRM_TSG_TIMESLICE_US`, `NVRM_ASYNC`, `WINE_NVK_EXPERIMENTAL` and
`WINE_NVK_PRESENT_PROFILE`.

**`NVRM_610_MAXPOWER_MW` is the notable one.** The driver sets a GPS power limit
and logs the result including a hardware readback:

```
nvrm: GPS max power %lu mW set rc 0x%x, reads back %u mW (rc 0x%x)
```

It is not set anywhere on the reference machine. This is the only indirect
reading of the GPU's power state available on this stack, given that no sysctl
reports clocks, and a conservative default power cap would explain a GPU sitting
at 100% load while its ALUs are idle enough for Ultra shading to be free.

Do not use `NVK_I_WANT_A_BROKEN_VULKAN_DRIVER`. The name is the documentation.

### Fixed — found by a sweep before release

* **`--help` printed shell code, or truncated its own option list.** Every tool
  built its usage text with a hardcoded line range (`sed -n '2,38p'`), which
  drifted whenever a header grew or shrank. `nvk-steam` and `nvk-setup` printed
  `set -u`, `emulate -L zsh` and variable assignments after their comments;
  `nvk-mkapp` and `nvk-profile` cut off before the end of their own options.
  All of them now print the leading comment block by detecting where it ends,
  which cannot drift, and a test asserts no tool's `--help` contains shell code.
* **`nvk-mkapp --env` accepted values that silently broke delivery.** `CX_ENV`
  is parsed with `shellwords`, so an unbalanced quote or a backslash makes
  CrossOver fail to parse it and drop **the whole set** — which would look
  exactly like the variable not arriving, the failure mode that cost most of a
  day here. Quotes and backslashes are now refused, matching `nvk-bottle`.
* **`--regenerate-all` moved launchers and left duplicates.** It passed its own
  default `--outdir` to every child invocation, so a launcher installed
  anywhere else was rebuilt in `~/Applications` while the original stayed put.
  Profiles now record `outdir`, and regeneration puts each launcher back where
  it was; an explicit `--outdir` still overrides.

### Added — automatic launcher icons

* `bin/nvk-icon` — finds an icon for a generated launcher and converts it to
  `.icns`. `nvk-mkapp` calls it whenever `--icon-from` is not given, so
  launchers now carry the right artwork without being told where it is.

Two sources, in preference order:

1. **CrossOver's own generated `.app`** for the program. CrossOver extracts the
   real Windows icon when it creates those bundles and stores it as a
   multi-resolution `.icns` — the best source available, and no conversion. The
   catch is that it is always named `CrossOverHelper.icns` whatever the program
   is, so matching has to be on the `.app`'s name. Verified distinct per app:
   Deadlock 81,895 bytes, Steam 78,847, Steam Support Center 67,789.
2. **Steam's library cache** for the appid. Newer Steam buries this in
   hash-named subdirectories, so it is searched rather than assumed:
   `logo.png` is preferred, then `library_capsule.jpg`, `library_600x900.jpg`,
   and the headers.

Squaring rule: artwork with transparency is **padded** (a wide logo keeps its
whole shape and the margin stays transparent), photographic artwork is
**centre-cropped** (a vertical capsule would otherwise get large bars).
Conversion uses `sips` and `iconutil`, both macOS built-ins, so this adds no
dependency.

Measured on the reference machine: Deadlock and Steam resolve to CrossOver's
extracted icons; Counter-Strike 2 has no CrossOver bundle and falls back to
Steam's `logo.png`, which converts to a clean transparent 1024px icon.

Found while looking for where CrossOver keeps icons, worth recording: a bottle's
generated programs live in `<bottles-parent>/Programs/<bottle>/` when the bottle
directory has been relocated, and under `~/Applications/CrossOver/` otherwise.
Nothing readable records which layout is in use, so `nvk-icon` tries both.

### Added — tooling

* `bin/nvk-flipstat` — reads the kext's presentation counters and deltas them
  around a session (`begin` / `end`). Presentation cost is the only part of the
  performance gap that can be measured directly on this stack; see the note on
  GPU clocks below for why this replaced the obvious approach.
* `bin/nvk-mdmp` — reads a Windows minidump without a Windows debugger:
  exception record, loaded graphics modules, and the engine's own fatal-error
  report. Source 2 embeds that report in the dump's comment stream and never
  writes it to `console.log`, because the process aborts before log flushing.
  Without this the native-Vulkan failure below is invisible.
* `docs/upstream/04-native-vulkan-swapchain-creation-fails.md`
* `docs/upstream/05-descriptor-buffer-unavailable.md`

### Changed

* `profiles/deadlock-1422450.conf` and `profiles/counter-strike-2-730.conf`
  return to `args=-dx11`. Both had been switched to `-vulkan` while testing the
  native Vulkan path; that path does not work (below), and leaving it in the
  profiles meant `nvk-mkapp --regenerate-all` would rebuild launchers that
  cannot start. How to retry it is documented in `docs/COMPATIBILITY.md` rather
  than left armed in a profile.

---

## Findings — 2026-11-23

### The goal is met, and beaten: quality settings are effectively free

**Ultra preset with FSR2 2x produced the same upper and lower frame-rate bounds
as low settings**, at no measurable cost. The stated target was medium settings
holding low-settings frame rates; Ultra does it.

This is the single most useful result on this page, and it says something
precise: **GPU shading is not the limiting factor on this stack.** Raising
shader quality, shadow quality, SSAO, bloom and texture detail changes nothing,
because the bottleneck is elsewhere. It also retrospectively explains why every
settings A/B in this file produced results inside the noise — they were all
adjusting something that was never the constraint.

Recommended configuration for the reference machine: **Ultra, FSR2 2x,
1920×1080, 180 Hz.**

### The real problem: scene-transition stalls

With quality settings ruled out, the remaining complaint is frame pacing, and
per-frame inspection localises it precisely. Frame times are smooth *within* a
view and spike enormously *between* views:

| State | Frame time |
|---|---|
| looking at low-detail geometry | ~9 ms, smooth (≈110 fps) |
| transitioning to high-detail geometry | **100–150 ms spike** |
| settled on high-detail geometry | ~20 ms, smooth (≈50 fps) |

**Localised with `DXVK_HUD=gpuload,drawcalls,pipelines,descriptors,memory`:**

| Reading | Observation |
|---|---|
| `gpuload` | **~100% essentially all the time**, rare brief dips |
| `drawcalls` | more than doubles on high-detail views |
| `pipelines` | rises at the transition spike, settles on both plateaus |
| `descriptors` | rises with scene detail |
| vidmem heap 0 | rises with scene detail |

### Not pixel-bound either — which narrows it to one cause

Further testing eliminated resolution as a factor entirely:

| Change | Effect |
|---|---|
| render resolution reduced (`mat_viewportscale` 0.67 → 0.5 → 0.4) | none measurable |
| every available upscaler type (FSR2 and alternatives) | all performed identically; FSR2 best image |
| upscaler sharpness | no effect on performance |
| `r_citadel_shadow_quality` 3 → 0 | **1–5 fps**, the only positive result |
| `NVK_CMDMEM_RECYCLE=1` | no apparent change |
| `NVK_DESC_QUARANTINE=0` | **large regression plus visible quality loss** |

Note Deadlock exposes upscaler *type* but no quality/performance tier, so the
render-scale probe had to go through `mat_viewportscale`, which FSR2 may
override — treat the resolution results as strong but not airtight.

Taken with the earlier results, frame cost is:

* **insensitive to pixel count** (resolution, upscalers)
* **insensitive to shader complexity** (Ultra is free)
* **proportional to draw count** (`drawcalls` doubles, frame time doubles;
  shadow quality, which re-draws geometry per cascade, is the only setting that
  helped)

A cost that scales only with the number of draws is a **fixed per-draw cost**.
That is upstream report 05 and essentially nothing else.

**This also forced a correction to report 03.** Compression savings scale with
render-target pixel traffic, so a workload indifferent to pixel count is
unlikely to be limited primarily by uncompressed render targets. The bug is
real and fires constantly — **88 refusals in one 137-line session log**, on
allocations of 8 MB and 10 MB (full-resolution render targets) — but the claim
that `gpuload` corroborated it as the *leading* cost has been withdrawn from
that report.

`NVK_DESC_QUARANTINE=0` making things worse rather than better is itself
informative: the descriptor path is both on the critical path and load-bearing
for correctness. Do not use it.

### Corrected: there are two regimes, with two different limits

`gpuload` is **not** always ~100%. In very light scenes it falls to **50–60%**,
and rises to 100% by the time frame times reach the usual ~9 ms. Quality presets
change none of this.

That replaces the single "GPU saturated" model with two:

| Regime | Frame time | `gpuload` | Limited by |
|---|---|---|---|
| light geometry | ~9 ms (≈110 fps) | **50–60%** | CPU / submission — the GPU is idling |
| normal to heavy geometry | 9 → 20 ms | ~100% | GPU, scaling with draw count |

So ~110 fps is a **CPU-side ceiling**: in the lightest scenes the GPU has
spare capacity and cannot be given work fast enough. Below that ceiling the GPU
becomes the limit, and its cost tracks draw count rather than shading.

This strengthens rather than weakens
[report 05](docs/upstream/05-descriptor-buffer-unavailable.md): without
`VK_EXT_descriptor_buffer`, descriptor sets cost CPU time to allocate and update
*and* GPU time to bind, so a per-draw descriptor cost is the one explanation that
accounts for both regimes at once. Descriptor buffers would address both.

It also explains why `gpuload` looked pinned earlier: the readings were taken
during ordinary play, which is mostly the second regime.

### Superseded: the GPU is saturated, but not by shader work

`gpuload` at 100% while **Ultra shader quality costs nothing** is the key
combination, and it resolves the apparent contradiction: the GPU is busy, but
not with arithmetic. Its ALUs have headroom — that is why Ultra is free — and
what saturates it is memory traffic and per-draw state handling.

That makes the two known bandwidth and state costs the dominant ones, and
restores this document's original ranking:

* **Framebuffer compression refused on every render target** (finding 3) is a
  constant tax on all render-target traffic. On a machine that is bandwidth-bound
  rather than compute-bound, this is the single largest item — which is where
  this project first placed it, before a mis-measurement of presentation cost
  pushed it down the list.
* **DXVK's legacy binding model** (report 05) imposes per-draw descriptor work.
  `drawcalls` and `descriptors` both rising with detail while shader quality is
  free is direct evidence: cost tracks *how many things are drawn*, not how
  expensive each one is to shade.

`pipelines` rising at the spike confirms the transition stall is pipeline
creation, even with the Mesa cache warm — a cache hit still has to build the
pipeline object.

### Earlier framing, superseded

Two separate phenomena, and they probably have different causes:

* **The plateau** (9 ms → 20 ms with scene detail) while *shader quality is
  free* was read as per-draw **CPU** cost. `gpuload` at ~100% corrected that:
  the cost is per-draw, but it is being paid on the GPU, not the CPU. The
  conclusion that it is draw-count-bound rather than shading-bound stands, and
  [upstream report 05](docs/upstream/05-descriptor-buffer-unavailable.md)
  remains the explanation.
* **The spike** (100–150 ms, once per transition) is a one-off cost on first
  encounter with new content. With the Mesa pipeline cache confirmed working,
  the remaining candidates are descriptor-pool growth, texture upload, and BAR1
  VRAM grants — sessions show 293–675 grants with matching releases.

Neither is presentation: the slowest flip recorded since boot is 26.6 ms.

What the evidence rules out so far:

* **Presentation** — `flip_us_max` is 26.6 ms since boot;
  `flip_latch_timeouts` is 1.
* **GPU shading** — Ultra costs nothing.
* **DXVK shader translation** — the debug log shows 5,552 shader compilations
  against 5,549 cache hits and 3 misses. DXVK's shader cache is working.
* **DXVK memory or allocation pressure** — the 993 KB debug log contains four
  warnings in total, none of them allocation-related, and 9 memory-region
  mappings.
* **Power management** — `nvrm_pm_waited` is 0.

That leaves driver-side pipeline creation and the game's own asset streaming as
the candidates, which points at the next item.

### RULED OUT: `spvcache`, and the pipeline cache works fine

`~/.cache/mesa_shader_cache` holds **330 MB**. NVK is Mesa, so that is the real
on-disk pipeline cache, and it has been working the whole time. Pipeline
compilation is cached across sessions.

`spvcache` stayed at 0 B after its ownership was fixed and a session played, so
it is not used by the Wine/NVK path. The ownership change is harmless and can be
left or reverted; the directory appears to be unused on this configuration.

The driver's own cache controls are standard Mesa, visible as strings in
`libvulkan_nouveau.dylib`: `MESA_SHADER_CACHE_DIR`,
`MESA_SHADER_CACHE_DISABLE`, `MESA_SHADER_CACHE_MAX_SIZE` and
`MESA_SHADER_CACHE_SHOW_STATS` — the last of which is the right tool if cache
behaviour ever is suspected, rather than guessing from directory sizes.

The superseded reasoning is kept below because the parallel to finding 1 was
plausible and someone will draw it again.

### Suspect (ruled out): the driver's SPIR-V cache is unwritable, and silently empty

```
$ ls -ld /Library/GPUBundles/nvmtl/spvcache /Library/GPUBundles/nvmtl/aircache
drwxr-xr-x  2 _windowserver  wheel   64 Nov 11 20:07  spvcache
drwxr-xr-x 14 _windowserver  wheel  448 Nov 23 08:31  aircache

$ touch /Library/GPUBundles/nvmtl/spvcache/.probe-test
touch: Permission denied
```

`spvcache` is owned by `_windowserver`, is **not writable by the user**, and has
been empty since the day it was created. `aircache` — written by WindowServer
itself, for the Metal translation path — holds 16 MB.

That asymmetry is the whole point: the Metal path runs inside WindowServer and
can write its cache, while the Wine/NVK path runs as the user and cannot. If
`spvcache` backs NVK's SPIR-V-to-ISA pipeline caching, then **no pipeline
compilation is ever cached across sessions**, and first-encounter compilation
would land exactly where the stalls are observed — on transition into geometry
whose materials have not been seen yet.

**This is the same failure mode as finding 1** (`failed-air`), already
documented here: a root- or WindowServer-owned directory under
`/Library/GPUBundles/`, a driver that probes writability and falls back
silently, and a user who never learns the cache is dead. The documented
workaround has the same shape:

```sh
sudo chown "$(id -un)":staff /Library/GPUBundles/nvmtl/spvcache
```

**Unconfirmed.** It is not established that `spvcache` serves the NVK path
rather than the zink or Metal paths, and the name is the main evidence. Test it
by fixing ownership, playing a session to populate it, then checking whether it
grows and whether the transition stalls shrink on a *second* session.

### Native Vulkan (`-vulkan`) does not work, and the cause is not Valve's

Both Source 2 titles fail identically and immediately:

```
vkCreateSwapchainKHR -> "Unknown VkResult value"
Failed to initialize video!
FATAL ERROR: AppSystemDict: Error in Init() of interface 'RenderDeviceMgr001'!
```

The user-visible symptom is a dock icon followed by exit status 1 with nothing
drawn, because the engine's fatal-error dialog cannot be displayed.

What this rules out, in case anyone retries it:

* The flag works. `Render system: Vulkan`, `rendersystemvulkan.dll` loaded,
  real vendor ID `0x10de` reported — this reached native NVK with DXVK out of
  the chain, exactly as intended.
* Device and physical-device creation both succeed. The failure is one call.
* `rendersystemvulkan.dll` and the Vulkan shader archives
  (`shaders_vulkan_*.vpk`) ship in the Windows depots of both games.
* `vulkan-1.dll` and `winevulkan.dll` are both present in the prefix and both
  load.
* Forcing a non-zero extent with `-w 1920 -h 1080` changes nothing.
* The crash is `0x80000003 BREAKPOINT` in `kernelbase.dll` — a deliberate
  engine abort, not a memory fault. Do not read it as a segfault.

Two separate defects, written up as upstream report 04: the swapchain refusal
itself, and the fact that the returned `VkResult` is not a value in the enum,
which is what made it undiagnosable. DXVK creates a swapchain on the same
bridge without trouble, so the WSI path is not broadly broken.

Worth knowing: the runtime's own README scopes support to "an x64 Windows D3D11
or D3D12 game", so a game driving `VK_KHR_swapchain` itself was never
qualified. This is a report about an unsupported configuration, not a
regression.

### Resolution scaling works, and tells us where the ceiling is

2560×1440 → 1920×1080, low settings, FSR2, Deadlock:

| Resolution | Frame rate | Per-frame copy |
|---|---|---|
| 2560×1440 | 35–130 fps | 14,745,600 B |
| 1920×1080 | 70–130 fps | 8,294,400 B |

A 44% cut in per-frame copy bytes roughly **doubled the floor and left the
ceiling untouched**. That asymmetry is the useful part: the lows were
bandwidth-bound and are now much more consistent, but something that is not
bandwidth is holding the top end at ~130 fps. A ceiling that will not rise when
bandwidth is freed points at a per-draw or per-submission CPU cost, which is
what upstream report 05 is about.

### GPU reclocking cannot be measured on this stack, and PM is not disabled

`-nvrmnopm` is **not** present in boot-args, so power management is not turned
off:

```
debug=0x100 keepsyms=1 ctrsmt=full -ibtcompatbeta revpatch=sbvmm nvfb=1
nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80
ipc_control_port_options=0 gfxrst=4 nvfbhidpi=1
```

Beyond that, the question is not answerable as usually posed. The kext exposes
49 `debug.nvrm*` sysctls and **none** reports clock, pstate, voltage or
frequency — only `debug.nvrm_pm_waited`. There is no clock readout to check, and
`powermetrics` does not know this GPU.

The resolution result above is the available substitute: a GPU pinned at idle
clocks would be hard bandwidth-bound and would have scaled its ceiling with
resolution. It did not. Low clocks are therefore unlikely to be the dominant
factor, which is as close to an answer as this stack permits.

### Measured: the presentation copy is cheap; the vsync cadence is the ceiling

Four Deadlock sessions of ~190 s each, measured with `nvk-flipstat`, all at
1920×1080 with FSR2 (`mat_viewportscale 0.67`):

| Run | Presented /s | vs low | Mean flip | % of refresh interval | Grant B/flip |
|---|---|---|---|---|---|
| low, 180 Hz | 88.4 | — | 3.183 ms | 57.3% | 120,506 |
| medium, 180 Hz | 69.1 | 78% | 3.262 ms | 58.7% | 150,160 |
| medium + `cachedDynamicResources`, 180 Hz | 82.9 | **94%** | 3.302 ms | 59.4% | **78,090** |
| medium, 120 Hz | 67.8 | 77% | 5.167 ms | 62.0% | 154,588 |

**This corrects the project's own model of the performance gap.**

*Mean time in flip is a wait, not work.* It tracks the display refresh interval,
not pixel count — 3.18 ms at 180 Hz (5.56 ms interval) against 5.17 ms at 120 Hz
(8.33 ms interval). In both cases it lands at 57–62% of one interval, where an
even phase distribution alone accounts for 50%. The residue above half-interval
is the only part that can be actual work: **0.4–0.5 ms per frame, or about 3.5–4.4%
of wall clock.** The earlier reading of 28–45% as presentation *cost* was wrong;
most of it is a vblank phase wait that would be there whatever was being copied.

So the full-frame copy per present, while real and measured, is not the
expensive item it was ranked as. Its direct time cost is small.

*Presentation lands on roughly every second vblank.* The low-settings run hit
88.4 presented frames per second against a 180 Hz panel — within 2% of exactly
half the refresh rate. The 120 Hz run gave 67.8 against a half-rate of 60. The
pattern is a frame that misses its vblank deadline and waits for the next one,
which caps presented frames near half the refresh rate regardless of how fast
the renderer runs. With mean flip occupying ~58% of each interval there is not
room to make every vblank.

*The FPS overlay is not measuring what reaches the screen.* Reported peaks of
195–240 fps against 69–88 frames per second actually presented means a majority
of rendered frames are discarded. Any tuning judged by the overlay is being
judged on frames nobody sees. This is why `nvk-flipstat` reports flip rate.

### `d3d11.cachedDynamicResources = a` — not established, and retracted

First measured as a 20% improvement (69.1 → 82.9 presented/s) with VRAM grant
traffic per frame apparently halved. **A repeat run at identical settings gave
64.4/s** — worse than medium without the option — and grant traffic per frame of
177,331 bytes, 2.3× the first run's 78,090.

| Run | Presented /s | Mean flip | Grant B/flip | Grants |
|---|---|---|---|---|
| medium, no option | 69.1 | 3.262 ms | 150,160 | 1.90 GiB |
| medium + option, run 1 | 82.9 | 3.302 ms | 78,090 | 1.19 GiB |
| medium + option, run 2 | 64.4 | 3.720 ms | 177,331 | 2.46 GiB |

The option is therefore **unproven, in either direction**. It may still help —
the reasoning behind it stands, since the device exposes no
`DEVICE_LOCAL | HOST_VISIBLE` memory type and every dynamic upload stages
through host memory — but this measurement cannot show it.

### The real finding: gameplay sessions cannot resolve effects this small

Three runs at medium settings on the same machine, same resolution, same
refresh rate, spanning **64.4 to 82.9 presented frames per second — a 29%
spread.** Grant traffic per frame varied by 2.3× across two runs of one
configuration. Mean time in flip ranged 3.18–3.72 ms at a fixed 180 Hz.

Deadlock's maps are large and scene complexity dominates: a bot match on a fixed
hero is still not a fixed workload, and the reference machine confirms the
variance is not avoidable by playing more carefully. Anything smaller than
roughly 30% is invisible to this method, which covers every tuning option tested
so far.

Consequences for anyone measuring on this stack:

* **One pair of runs is not a result.** Both the earlier 1440p→1080p
  improvement and this option were read from single runs; only the first was
  large enough to survive.
* **A deterministic workload is required** for anything subtler. Source 2 demo
  playback (`record` / `playdemo`) replays identical frames and is the obvious
  candidate; a fixed spectator camera is a weaker substitute.
* **Medians of several runs** are the fallback where a demo is not available.

What survives the variance, because the effects are large or structural:

* Presented frames are a fraction of reported frames (64–88/s against overlay
  readings of 195–240).
* Mean time in flip tracks refresh interval, not pixel count — every 180 Hz run
  fell in 3.18–3.72 ms against 5.17 ms at 120 Hz, which is outside that spread.
* Presentation lands on roughly every second vblank; no run has exceeded 88.4/s
  against a half-refresh figure of 90.
* 120 Hz is worse than 180 Hz.

### `IMMEDIATE` present mode is granted, then ignored

Settled by one debug-level run with `dxgi.syncInterval = 0`:

```
info:    Present mode: VK_PRESENT_MODE_IMMEDIATE_KHR (dynamic: no)
info:    Buffer size:  2560x1440
info:    Image count:  3
NVK Bridge: swapchain 2560x1440, 3 Vulkan images, 3 Metal slots
```

DXVK asks not to be synchronised to vblank, and the Vulkan layer agrees — three
images, three Metal slots, `IMMEDIATE` reported as the active mode. The kext
latches every flip to vblank regardless (`flip_interval = 1`,
`flip_latch_waits` tracking `flip_n` one-for-one, `late` and `deferred` both 0).

So the vsync behaviour is **not** fixable from DXVK, the application, or this
repository's configuration. Written up as
[upstream report 06](docs/upstream/06-immediate-present-mode-not-honoured.md),
which is the one to send first.

### Correction: lowering the game resolution does not reduce the presentation copy

The swapchain in that run is **2560×1440** — the desktop resolution — during a
session configured for 1920×1080 with `-w 1920 -h 1080` and
`defaultres 1920 / defaultresheight 1080` in `video.txt`. It was created once
and never recreated.

Source 2 in fullscreen takes a swapchain the size of the display and renders
internally at the chosen resolution, so **every "1080p" session on this machine
has been paying the full 1440p presentation copy**: 14,745,600 bytes per
present, not 8,294,400.

This corrects a claim this project has carried since its first release, that
lowering output resolution "attacks the presentation copy directly". It does
not. The measured 1440p→1080p improvement was entirely a reduction in *render*
cost; the copy never got cheaper.

The copy follows the **desktop** resolution, so the untested lever is setting
the macOS display mode to 1920×1080 at 180 Hz rather than changing the game's
resolution. Given that the copy's direct time cost measured only 0.4–0.5 ms per
frame, the expected gain is in bandwidth rather than in flip time, and it may
show up only as hitting the 90 rung more often.

### WITHDRAWN: the `refresh / n` quantisation model

**Disproven by per-frame inspection.** DXVK's `frametimes` overlay shows a
*smooth*, scene-dependent distribution — not bands at multiples of the refresh
interval. The model below was built on aggregate counters, which cannot
distinguish quantisation from a smooth limit, and it was asserted here before
that was checked. The measured data is kept because it is still valid as a
record of presented throughput; the explanation is wrong.

What actually produces the bad frame pacing is described under *scene-transition
stalls*, further down. It is not a presentation problem: the slowest flip
recorded since boot is 26.6 ms, against stalls of ~1000 ms.

Five Deadlock runs at 1920×1080 / 180 Hz, presented frames per second:

| Settings | Presented /s |
|---|---|
| low | 88.4 |
| medium | 69.1 |
| medium + `cachedDynamicResources` | 82.9 |
| medium + `cachedDynamicResources`, repeat | 64.4 |
| medium + attempted `r_low_latency 0` / blur / SSAO | 61.6 |

Every value falls between **60 and 90** — which are exactly 180/3 and 180/2. This
coincidence drove the withdrawn model above; the GPU's own capability sits at
roughly the same place, which is the simpler explanation.
Presentation is vsync-latched (`flip_interval = 1`, and `flip_latch_waits`
tracks `flip_n` one-for-one), so a present lands on the 2nd or 3rd vblank and
the achievable rates are quantised to 90, 60, 45, 36. Nothing in between is
reachable.

That reframes the 29–35% spread. It is not primarily sampling noise: it is the
*ratio* of 90-fps frames to 60-fps frames shifting as scene load moves, and the
low-settings run sitting at 88.4 is a session that almost always made the 2nd
vblank.

It also explains the subjective report that perceived frame rate feels similar
across every configuration while feeling inconsistent within each one. Alternating
between 11.1 ms and 16.7 ms frame times is far more visible than the average
suggests, and no graphics setting removes it — settings only shift how often each
rate is hit.

**Consequence: tuning settings cannot fix this, and cannot be measured against
it.** Until presentation is unlatched from vblank, every option tested lands
inside the same quantisation band.

### The flip sysctls are self-documenting — read them before theorising

`sysctl -d` returns a description for every `debug.nvrm*` entry. This should have
been the first thing checked, and reading them corrects several things recorded
above:

```
nvrmfb_flip_interval  minPresentInterval of the pure (zero-copy) flip;
                      tearing stays off
nvrmfb_flip_n         pure flips timed
nvrmfb_flip_us_sum    microseconds spent in pure-flip applyModeSetConfig
nvrmfb_flip_latch     1 = a committed flip waits for its completion before a
                      surface retires (0 = debug bypass, 2 = deferred: the
                      next submit verifies it)
nvrmfb_flip_latch_late      presents skipped because the previous flip was
                            still on its way to the panel
nvrmfb_flip_latch_deferred  flips verified by the next submit instead of
                            waited for
nvrmfb_flip_lean      1 = lean pure flip (surface only)
```

Corrections that follow:

* **`flip_interval = 0` is the wrong lever.** It is a *minPresentInterval*, and
  `1` already permits one flip per vblank — so it is not what caps throughput.
  The description also says "tearing stays off" regardless, so setting it to `0`
  would not unsynchronise anything. An earlier entry here recommended testing
  it; that recommendation was wrong.
* **The risk was overstated.** "Tearing stays off" by construction, and
  `flip_latch = 2` is a *named, documented mode*, not a debug bypass — `0` is
  the bypass. The plausible failure mode is a visual artefact from a surface
  retiring early, not the GPU hang previously described.
* **`flip_latch = 2` ("deferred") is the real candidate.** With `latch = 1`
  every flip waits for completion before its surface retires, and
  `flip_latch_waits` tracks `flip_n` one-for-one in every session. Deferring
  that verification to the next submit is the one documented way to remove a
  serialisation from this path.
* **`flip_n` counts "pure flips"** — the zero-copy framebuffer flip path. The
  NVK bridge reports `presentation=gpu-copy` for the game, so these counters are
  the *display* flip path, not the game's Vulkan presents. They are still the
  final step that puts pixels on the panel, but equating them with presented
  game frames needs validating rather than assuming (see below).
* **`flip_latch_late = 0` in every session**, and its description is "presents
  skipped because the previous flip was still on its way to the panel". So the
  flip path is not reporting dropped presents. Frames beyond the flip rate are
  coalesced in the three-slot drawable queue instead, which is undetectable from
  the application side.

### Calibrated: flip rate does track the game's presented frames

`fps_max 60` in Deadlock, measured over 230 s:

```
mean flip rate         55.6 /s
mean time in flip      3.101 ms
total time in flip     17.2% of wall clock
grant bytes per flip   94,559
```

55.6 against a cap of 60 — the shortfall being scenes that cannot hold the cap.
**The counters follow the game's presents, not compositor scanout**, despite
`flip_n` being documented as counting "pure" zero-copy flips while the bridge
reports `presentation=gpu-copy`. Every earlier measurement in this file stands
as a measure of presented frames.

Also worth noting: at a 60 cap, time in flip fell to its lowest observed value
(3.101 ms, 17.2% of wall clock) and VRAM grant traffic per frame to 94,559
bytes. A capped game stresses the whole path less.

### But averages cannot test the quantisation model, and never could

The `refresh / n` hypothesis is **not** confirmed by the above, and on reflection
it is not testable with aggregate counters at all. An engine pacing toward a
frame-rate target averages to that target whether or not frame times are
quantised — alternating 11.1 ms and 22.2 ms averages to the same number as a
steady 16.7 ms. A cap of 60 is additionally a poor discriminator because
180/3 = 60 sits exactly on a rung.

So the quantisation model remains **plausible but unproven**: the 60–90 band
across five uncapped sessions is suggestive, and the low-settings run landing at
88.4 against a 90 rung is suggestive, but the GPU's own capability sits at
roughly the same place, which makes the two indistinguishable by average.

Testing it needs **per-frame timing, not aggregates.** `DXVK_HUD` with the
`frametimes` element shows the distribution directly: if frame times cluster at
multiples of the refresh interval (5.56, 11.1, 16.7, 22.2 ms at 180 Hz) the
model is real; if they form a smooth spread, it is not. That element is normally
turned off for measurement because it costs time, but it is the right instrument
for this specific question.

### Practical consequence: align the frame cap to a rung

If quantisation is real, the most useful thing available locally is not a higher
average but a *stable* one. Capping the game at a rung — 90 or 60 on a 180 Hz
panel — stops the engine overshooting into work that is then discarded, and
should remove the oscillation that dominates the subjective experience.

Untested, and judged by feel rather than by counter: a steady 60 may well be
preferable to an alternating 60/90 averaging 75. Worth trying `fps_max 90` at
low settings (88.4/s was achieved uncapped, so the rung is reachable) and
`fps_max 60` at medium.

### Lowering display refresh does not help


120 Hz was worse on every measure than 180 Hz: fewer presented frames (67.8 vs
82.9 at the same settings), a longer mean flip (5.167 ms vs 3.302 ms), and a
larger share of wall clock. Because the presented-frame ceiling is near half the
refresh rate, reducing refresh lowers the ceiling. Keep the panel at its highest
mode.

### `WINEMSYNC` is already enabled — ruled out, not a lever

CrossOver 26.3's `ntdll.so` contains the `WINEMSYNC` environment string, the
runtime's README recommends `WINEMSYNC=1` for Mach-based synchronisation, and
`nvk-bottle` has written it into the managed block all along. The reference
bottle has `"WINEMSYNC" = "1"` set.

Recorded because it is the obvious thing to reach for when a workload looks
CPU-bound, and because it is easy to conclude it is missing: it sits outside the
`DXVK_*` and `DYLD_*` keys that get grepped for, so a filtered look at
`cxbottle.conf` can miss it. Check with `nvk-bottle status <bottle>`, which
prints the whole managed block, rather than grepping.

CPU-side synchronisation is therefore **not** an available improvement here. The
ceiling described above is CPU-bound with msync already in place.

### Measurement hygiene

The reference bottle runs with `DXVK_HUD=devinfo,fps,frametimes` and
`DXVK_LOG_LEVEL=info`. The `frametimes` graph is the most expensive HUD element
and info-level logging writes continuously. Both are useful while diagnosing and
both should be off when recording a number.

---

## 2026-11-22 — Confirmed functionality, public release

First public state. Repository structure, licensing and documentation; the
machine-agnostic `nvk-doctor` preflight gate; Steam discovery with offline
fixtures; the per-game profile format and `nvk-mkapp --regenerate-all`; and
`nvk-setup` as a guided front door.

Driver findings 01–03 written up as submission-ready upstream reports:
the AIR translator rejecting a valid Apple-emitted FSR2 shader, sRGB storage
images silently discarding writes, and framebuffer compression refused on every
render target.

Baseline measurement: Deadlock, RTX 4070, low settings, FSR2 2x, 2560×1440 —
35–130 fps over 20,299 frames.
