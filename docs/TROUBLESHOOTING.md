# Troubleshooting

Start with `bin/nvk-doctor`. It is read-only, never needs sudo, and its output
is also what you should attach to any bug report. Add `--bottle NAME` to check a
bottle's DXVK and configuration too, or `--all-bottles` for every one it finds.

Its exit status is the gate:

| Status | Meaning |
|---|---|
| `0` | Everything required is present and correct. |
| `2` | Usable, but at least one check wants attention. |
| `1` | At least one fatal problem. Do not continue. |

It compares the DXVK DLLs installed in a bottle against the runtime's own
`SHA256SUMS`, so it stays correct across runtime updates rather than checking
hashes written down when it was authored.

Generated launchers log to `~/Library/Logs/nvk-<name>.log`. DXVK logs land in
`<bottle>/drive_c/dxvk/`.

If a launcher is wrong rather than broken — the wrong executable, missing
arguments — fix its profile in `profiles/` and run `nvk-mkapp --profile
<file>`, rather than editing the generated `.app`. The `.app` is an artefact;
the profile is the record. `nvk-mkapp --regenerate-all` rebuilds every one of
them, which is what to run after a runtime or CrossOver update.

---

## "Failed to create DirectX 11 render device!"

**Cause:** `CX_GRAPHICS_BACKEND` is set, almost certainly to `wine`. That routes
D3D through wined3d on OpenGL, and macOS OpenGL caps at 4.1, which cannot do
Shader Model 5.

**Fix:** remove it from `cxbottle.conf`. `nvk-bottle setup` strips it for you.

---

## "Unable to find the 'Steam' bottle"

**Cause:** CrossOver's `--bottle NAME` searches only its two default bottle
directories. If your bottle lives on another volume, a GUI-launched process
cannot find it — even though it works from your shell, because your shell has
environment the GUI process does not.

**Fix:** set `CX_BOTTLE_PATH` to the directory *containing* the bottle.
Generated launchers pin this at generation time.

---

## The game launches but runs on the wrong renderer

Check the DXVK log for `Found device:`. If it names something other than your
NVIDIA card under NVK, the `DYLD_LIBRARY_PATH` did not reach the game process.

**Cause:** macOS strips `DYLD_*` across hardened-runtime exec boundaries, so it
cannot be inherited through Steam's helper chain. Setting it in your shell and
then launching via Steam's Play button will not work.

**Fix:** launch through a generated `.app`, which sets it in the process that
becomes the game. Alternatively `nvk-bottle setup <bottle> --dyld` writes it
into `cxbottle.conf`, which does survive — at the cost of applying to
everything in that bottle.

---

## DXGI reports an AMD GPU

**This is normal and is not a problem.** DXVK's NVAPI workaround deliberately
reports a synthetic AMD vendor/device ID (`0x1002` / `0x73df`). Your actual
device is the one on the `Found device:` line.

---

## Nothing launches: "Abort trap: 6", exit status 134

**Symptom:** every app in the bottle fails immediately, Steam included, and the
log shows `dyld` refusing to start the process:

```
dyld[NNNNN]: terminating because inserted dylib '/tmp/hook.dylib' could not be
loaded: tried: ... (no such file)
launch: line NN: NNNNN Abort trap: 6   env WINEPREFIX=... "$CXW" --bottle ...
exited rc=134
```

**Cause:** something has added a `DYLD_INSERT_LIBRARIES` assignment to
CrossOver's own `wine` script, pointing at a file under `/tmp`. Since `/tmp` is
wiped on reboot, this works until the first restart and then breaks every
launch. 134 is 128 + 6, i.e. `SIGABRT` — `dyld` aborts before Wine starts, so
nothing in this project's logs explains it.

**Check** whether CrossOver's `wine` has been modified. Stock CrossOver does not
insert dylibs:

```sh
W=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine
grep -n 'DYLD_INSERT_LIBRARIES' "$W"
ls -la@ "$(dirname "$W")" | head
```

`wine` carrying a different modification date from its siblings — and having
lost the extended attributes they still show — means it was rewritten rather
than shipped that way.

**Fix:** back it up and comment the assignment out.

```sh
cp -p "$W" "$W.bak"
# then comment out the `if ($cmd =~ /wineloader/) { ... }` block around it
perl -c "$W"     # must print "syntax OK"
```

Reinstalling CrossOver also restores the stock script.

This is not part of the NullMoth driver integration — its scripts do not
reference `hook.dylib` — so removing the injection does not affect NVK.

---

## No DXVK log appears at all

**Cause:** `DXVK_LOG_PATH` was given a unix path. It must be a **Windows** path
such as `C:\dxvk`. A unix path fails silently, producing no log and no error.

Related trap when writing your own scripts: `echo` consumes backslash escapes
in some shells (`\c` truncates the rest of the line). Use `printf` for anything
containing a Windows path.

---

## Characters and HUD text are missing; scenery renders fine

**Cause:** the DXVK descriptor-buffer path.

**Fix:** `dxvk.enableDescriptorBuffer = False`. `nvk-bottle setup` writes this
into the bottle's `DXVK_CONFIG` by default. Confirm with
`nvk-bottle status <bottle>`.

---

## Black or frozen frames with nothing obvious in the log

Likely the sRGB storage-image bug — shader writes are being silently discarded.
See [DRIVER-ISSUES.md](DRIVER-ISSUES.md) §2. There is no workaround in this
repo's control; it needs a driver fix.

---

## Poor frame rate

Expected, to a degree — see the README's Performance section. In order:

* **Turn on the driver's experimental features.** They ship off, they are the
  largest measured improvement, and almost nobody knows they exist:
  ```sh
  sudo /Library/NullMoth/nullmoth-setup.sh --experimental gameprio,tile,tgp
  ```
  `gameprio` alone took frame-time spikes from 41 ms to 10–15 ms. `tgp` needs a
  reboot. Do **not** add `icb` — it drives GPU utilisation up while making both
  frame time and frame rate worse.
* **Do not lower quality settings first.** They are effectively free on this
  stack — Ultra measured the same as Low. Lower the *resolution* instead, which
  is a real lever.
* `WINEMSYNC=1` is set. `nvk-bottle` writes it, but a bottle configured by an
  older version may not have it; check with `nvk-bottle status <bottle>` rather
  than grepping, since it is easy to miss.
* Framebuffer compression is refused on every target (DRIVER-ISSUES §3). Nothing
  you can configure changes this today.

**Measure with `nvk-flipstat`, not with an FPS overlay.** The overlay counts
frames the renderer produced; on the reference machine it reported 195–240 fps
during sessions that actually presented 61–88. Note also that gameplay
run-to-run variance reaches 35%, so compare a fixed viewpoint before and after
a change rather than two whole sessions.

---

## `nvk-bottle setup` refuses to run

It will not edit a bottle while `wineserver` is running, because CrossOver can
rewrite `cxbottle.conf` underneath you. Use "Quit All Applications" on the
bottle in CrossOver, then re-run.

---

## Undoing everything

```sh
./bin/nvk-bottle undo <bottle>
```

This restores the runtime's original DLLs and copies `cxbottle.conf.bak` back
over `cxbottle.conf`. Generated `.app` bundles are inert once the bottle is
restored; delete them from `~/Applications` if you want them gone.

---

## Filing a bug

Include:

1. `bin/nvk-doctor` output in full
2. The launcher log from `~/Library/Logs/`
3. The DXVK log from `<bottle>/drive_c/dxvk/`
4. Game name, and whether it was launched via the generated app or Steam

If the problem is visual corruption or a translator refusal, also check
`/Library/GPUBundles/nvmtl/failed-air/` — and note that this directory does not
exist by default, so an empty result there may mean "not collected" rather than
"nothing wrong". See [DRIVER-ISSUES.md](DRIVER-ISSUES.md) §1.
