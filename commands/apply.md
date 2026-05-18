---
description: vd apply — apply manifests, flags, prune semantics
---

Display the following cheat sheet to the user, verbatim, as markdown.

# `vd apply` — apply HCL manifests

```sh
vd apply -f voodu.hcl                          # single file
vd apply -f deployments.hcl -f ingresses.hcl   # multiple -f
vd apply -f ./manifests/                       # directory (every .hcl/.voodu/.yml)
vd apply -f web                                # bare name resolves web.voodu/.hcl/.yml/...
vd apply -f voodu.hcl -r prod                  # ship to remote "prod"
```

## Flags

| Flag | What it does |
|---|---|
| `-f <file\|dir>` | Manifest(s). Repeatable. |
| `-r <remote>` | SSH remote (defaults to the `voodu` git remote). |
| `--prune` | **Opt-in.** Delete resources in the same `(scope, kind)` missing from the manifest. |
| `-o json` | JSON output. |

## Default is upsert-only

Without `--prune`, `apply` only creates/updates — never deletes. To prune:

```sh
vd apply -f voodu.hcl --prune
```

Prune is per `(scope, kind)`. Other kinds in the same scope stay untouched.

## Variable interpolation

`${VAR}` and `${VAR:-default}` are resolved on **your machine** before the tarball ships.

```hcl
deployment "clowk-lp" "web" {
  image = "ghcr.io/clowk/lp:${IMAGE_TAG:-latest}"
}
```

```sh
IMAGE_TAG=v1.4.2 vd apply -f voodu.hcl -r prod
```

## File extensions

All parse as HCL (or YAML with the same schema): `.hcl`, `.voodu`, `.vdu`, `.vd`, `.yml`, `.yaml`.

## Build-mode vs image-mode

- With `image = "..."` → controller pulls from the registry.
- Without `image` (uses `path`, `lang`) → CLI tarballs the CWD and ships it via SSH; server builds.

Force a rebuild: `VOODU_FORCE_REBUILD=1 vd apply -f voodu.hcl`.

## Common recipes

```sh
# CI: gate on changes
vd diff -f voodu.hcl --detailed-exitcode

# Fan-out across hosts
for r in prod-1 prod-2 prod-3; do vd apply -f voodu.hcl -r $r; done

# Apply just one kind without touching siblings
vd apply -f deployments.hcl                   # leaves ingresses alone (no --prune)
```
