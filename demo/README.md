# Interactive Scour Demo

This disposable workspace demonstrates every implemented Scour rule without
modifying the automated regression fixtures. Recreate it at any time:

```sh
nimble build
bash demo/setup.sh
cd demo/workspace
../../scour --all
../../scour triage --all
../../scour
../../scour rules
```

`--all` reports the 12 static mistakes committed from `demo/template/`.
The default scan includes `package-lock-drift` because setup stages a manifest
edit under `staged/` while leaving its `package-lock.json` unchanged.
