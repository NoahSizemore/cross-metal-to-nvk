# Profiles

One file per game, describing everything needed to regenerate its launcher.

Profiles are the output of record: `nvk-mkapp` builds a `.app` *from* a profile,
so after a runtime or CrossOver update every launcher can be rebuilt in bulk
rather than reconstructed from memory.

They are also meant to be **shared**. For that reason a profile is flat
`key=value` text that is parsed line by line and **never `source`d** — sourcing
a file someone sent you is arbitrary code execution.

Format (schema 1):

```
schema=1
appid=1422450
name=Deadlock
bottle=Steam
bottle_dir=/Volumes/Storage/CrossOver/Bottles
exe_win=C:\...\game\bin\win64\deadlock.exe
args=-dx11
needs_steam=no
dxvk_config=dxvk.enableDescriptorBuffer = False
notes=Free-text findings worth passing on.
```

The format does not assume Steam, even though discovery currently does.
