# Profiles

One file per game, describing everything needed to regenerate its launcher.

Profiles are the output of record: `nvk-mkapp` builds a `.app` *from* a profile,
so after a runtime or CrossOver update every launcher can be rebuilt in bulk
rather than reconstructed from memory.

They are also meant to be **shared**. For that reason a profile is flat
`key=value` text that is parsed line by line and **never `source`d** — sourcing
a file someone sent you is arbitrary code execution.

Three keys describe *your* machine rather than the game: `bottle_dir`,
`exe_unix` and `outdir`. They are recorded for diagnosis and for rebuilding in
place, and none is needed to rebuild a launcher elsewhere — `nvk-mkapp`
resolves the prefix from the bottle name. **Delete them before sending a
profile to anyone.** They are your filesystem layout, and they are wrong for
the recipient regardless.

For the same reason this directory's `*.conf` files are not committed. Yours
stay local; the format below is the shared part.

Format (schema 1):

```
schema=1
appid=1422450
name=Deadlock
bottle=Steam
bottle_dir=/path/to/your/CrossOver/Bottles
exe_win=C:\...\game\bin\win64\deadlock.exe
args=-dx11
needs_steam=no
dxvk_config=dxvk.enableDescriptorBuffer = False
env=DXVK_HUD=fps;NVRM_ONE_CONN_PER_MAP=1
outdir=/Users/you/Applications
notes=Free-text findings worth passing on.
```

Two of those need explaining.

`env` is the set of variables the launcher exports, as `KEY=VALUE` pairs
separated by semicolons. It is delivered through CrossOver's `CX_ENV`, which is
the only channel that reaches **native** code — `cxbottle.conf` reaches
Windows-side code such as DXVK but not the NVK dylib, and a plain `export` in
the launcher does not survive CrossOver rebuilding the environment. Because
`CX_ENV` is split with `shellwords`, a value may not contain whitespace, a
quote or a backslash, and `nvk-mkapp --env` refuses those rather than letting
CrossOver silently drop the whole set.

`outdir` is where the launcher was installed, so `--regenerate-all` puts it
back there instead of in the default directory and leaving the original behind
as a stale duplicate. An explicit `--outdir` still wins.

The format does not assume Steam, even though discovery currently does.
