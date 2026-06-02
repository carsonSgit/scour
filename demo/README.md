# Interactive Scour Demo

This disposable workspace demonstrates every implemented Scour rule without
modifying the automated regression fixtures. Recreate it at any time:

```sh
bash demo/install.sh
bash demo/run.sh
```

`--all` reports the 12 static mistakes committed from `demo/template/`.
The default scan includes `package-lock-drift` because setup stages a manifest
edit under `staged/` while leaving its `package-lock.json` unchanged.

The interactive run script adds a React Doctor-style score via `scour --score`,
persists scan outputs under `demo/reports`, writes
`demo/reports/scour-doctor.txt` via `scour --format doctor`, and points to the
highest-value `scour explain <rule>` outputs for the walkthrough.

Optional side-by-side comparison with React Doctor:

```sh
bash demo/run.sh --with-react-doctor
```

That comparison uses `demo/react-doctor-workspace`, a dedicated React sample
that keeps the main Scour demo workspace unchanged. It stays optional because
it depends on `npx` and package resolution outside this repository.
