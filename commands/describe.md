---
description: vd describe — full state for a resource (manifest + status + pods)
---

Display the following cheat sheet to the user, verbatim, as markdown.

# `vd describe` — full resource state

```sh
vd describe deployment clowk-lp/web    # manifest + status + pods
vd describe statefulset data/pg
vd describe ingress clowk-lp/web
vd describe job clowk-lp/migrate
vd describe cronjob clowk-lp/nightly-backup
vd describe pod clowk-lp-web.abc123    # single container detail
```

`vd get pod <ref>` is an alias for `vd describe pod`.

## What's in the output

- **Manifest**: the reconciled spec as the controller stores it (after defaults, after `${asset.…}` resolution).
- **Status**: most recent reconcile event, error messages, last applied at.
- **Pods**: every container created for this resource, with state, age, exit code.

## Recipes

```sh
# Check why a deploy didn't roll:
vd describe deployment clowk-lp/web

# Find which assets resolved into a volume mount:
vd describe statefulset data/pg | grep asset

# Inspect a cronjob's recent runs:
vd describe cronjob clowk-lp/nightly-backup
```
