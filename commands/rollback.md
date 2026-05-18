---
description: vd rollback — revert a deployment to a past release
---

Display the following cheat sheet to the user, verbatim, as markdown.

# `vd rollback` — revert to a past release

```sh
vd rollback clowk-lp/web                # previous release
vd rollback clowk-lp/web release-42     # specific release
```

Re-applies a past release's spec snapshot. Release history is retained up to `keep_releases` (default ~10, configurable in HCL).

## Inspect releases

```sh
vd release clowk-lp/web list            # list releases with IDs
vd describe deployment clowk-lp/web     # current state + recent releases
```

## When to reach for it

- A bad image got promoted to `:latest` and is failing health checks
- A migration broke something and you need to fall back to the previous image
- You want to compare current behaviour to a known-good past spec

## After rolling back

The rollback creates a **new release** that points at the old spec. Future deploys overwrite it normally — there's no special "frozen" state.

```sh
vd rollback clowk-lp/web
vd release clowk-lp/web list            # newest entry is the rollback
```
