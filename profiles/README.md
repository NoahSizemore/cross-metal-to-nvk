# Profiles

One file per game, describing everything needed to regenerate its launcher.

Profiles are the output of record: `nvk-mkapp` builds a `.app` *from* a profile,
so after a runtime or CrossOver update every launcher can be rebuilt in bulk
rather than reconstructed from memory.

They are also meant to be **shared**. For that reason a profile is flat
`key=value` text that is parsed line by line and **never `source`d** — sourcing
a file someone sent you is arbitrary code execution.

Two keys describe *your* machine rather than the game: `bottle_dir` and
`exe_unix`. They are recorded for diagnosis, and neither is needed to rebuild a
launcher — `nvk-mkapp` resolves the prefix from the bottle name. **Delete both
before sending a profile to anyone.** They are your filesystem layout, and they
are wrong for the recipient regardless.

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
notes=Free-text findings worth passing on.
```

The format does not assume Steam, even though discovery currently does.
