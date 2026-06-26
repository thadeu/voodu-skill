# `vd delete` — remove resources

Five shapes, in order of how often you'll reach for them:

```sh
vd delete -f voodu.hcl                       # everything declared in the manifest
vd delete clowk-lp/web                       # one resource (auto-resolves kind)
vd delete deployment/clowk-lp/web            # one resource, explicit kind
vd delete clowk-lp                           # entire scope
vd delete statefulset/data/pg.0              # single pod by ordinal
```

## `--prune` flag (statefulset-only consequence)

For statefulsets, `--prune` also wipes the underlying Docker volumes:

```sh
vd delete statefulset/data/pg --prune        # IRREVERSIBLE: pod + volumes
```

Without `--prune`, volumes are kept. You can re-apply the manifest later and the data is still there.

## Recipes

```sh
# Tear down a whole stack:
vd delete -f voodu.hcl

# Drop one bad pod and let the controller recreate it:
vd delete deployment/clowk-lp/web.abc123

# Nuke an entire scope (no volumes):
vd delete clowk-lp

# Nuke a stateful scope including data (use with care):
vd delete data --prune
```
