# Fixtures

Sample Steam metadata for testing discovery logic without a Steam install.

The reference machine has exactly one Steam bottle, one library root and one
game, so filesystem-driven testing cannot cover the layouts this tooling claims
to support: multiple library roots, libraries on other volumes, install
directory names that differ from store names, and games whose executable is not
where the last game's was.

Discovery is therefore written as parsing over these fixtures, kept separate
from the filesystem walking that feeds it. Add a fixture whenever a real-world
layout breaks something.

Expected contents:

* `libraryfolders.vdf` — single-root and multi-root variants
* `appmanifest_*.acf` — including a game whose `installdir` differs from `name`
* `dosdevices/` — symlink trees for unix↔Windows path mapping, including a
  library mapped to a drive letter other than `C:`
