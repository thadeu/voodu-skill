---
description: vd diff — preview what an apply would do
---

Display the following cheat sheet to the user, verbatim, as markdown.

# `vd diff` — preview changes

```sh
vd diff -f voodu.hcl
vd diff -f voodu.hcl --prune                # include "would prune" section
vd diff -f voodu.hcl --detailed-exitcode    # CI: 0=clean, 1=err, 2=changes
vd diff -f voodu.hcl -r prod                # diff against a specific remote
```

## Output markers

| Marker | Meaning |
|---|---|
| `~ kind/scope/name` | Exists, spec would change. One line per differing field. |
| `+ kind/scope/name (new)` | Would be created. |
| `= kind/scope/name (unchanged)` | Already in sync. |
| `--- Would prune ---` | Would be deleted by `apply --prune` (shown only with `--prune`). |

## CI-friendly exit codes

```sh
vd diff -f voodu.hcl --detailed-exitcode
# 0 = no changes
# 1 = error (controller unreachable, invalid manifest, ...)
# 2 = pending changes
```

Common CI flow: `vd diff --detailed-exitcode` on PR → fail when state drifts.

## Example output

```
~ deployment/clowk/web
    ~ image     "nginx:1.26"  ->  "nginx:1.27"
    ~ replicas  1  ->  2
    + lang.name  "bun"
= ingress/clowk/web (unchanged)

--- Would prune (pass --prune to delete) ---
- deployment/clowk/old-worker

1 to modify, 1 to prune
```
