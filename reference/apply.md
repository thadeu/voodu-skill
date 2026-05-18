# apply / diff / delete

## `vd apply` — apply a manifest

```sh
vd apply -f voodu.hcl                          # single file
vd apply -f deployments.hcl -f ingresses.hcl   # multiple -f
vd apply -f ./manifests/                       # directory (every .hcl/.voodu/.yml)
vd apply -f web                                # bare name resolves web.voodu/.hcl/.yml/...
vd apply -f voodu.hcl -r prod                  # ship to remote "prod"
```

### Main flags

| Flag | What it does |
|---|---|
| `-f <file\|dir>` | Manifest(s). Repeatable. |
| `-r <remote>` | SSH remote (defaults to the `voodu` git remote). |
| `--prune` | **Opt-in.** Delete resources in the same `(scope, kind)` that aren't in this apply. |
| `-o json` | JSON output. |

### Default: upsert-only

Without `--prune`, `apply` only adds/updates resources — it never deletes. To prune declaratively, opt in:

```sh
vd apply -f voodu.hcl --prune
```

That turns the apply into a **source-of-truth** statement scoped to each `(scope, kind)` pair:

```
Manifest has:  deployment "clowk" "web"
Controller:    deployment "clowk" "web" + deployment "clowk" "old"

vd apply --prune  → "old" is deleted.
vd apply          → "old" stays.
```

Other kinds (ingress, statefulset) in the same scope are untouched — prune is per `(scope, kind)`.

> Common CI flow: `vd diff --prune` on the PR to surface what would disappear; `vd apply --prune` on merge.

### Variable interpolation in manifests

`${VAR}` and `${VAR:-default}` are resolved **on your machine** before the tarball ships:

```hcl
deployment "clowk-lp" "web" {
  image = "ghcr.io/clowk/lp:${IMAGE_TAG:-latest}"
}
```

```sh
IMAGE_TAG=v1.4.2 vd apply -f voodu.hcl -r prod
```

## `vd diff` — preview

```sh
vd diff -f voodu.hcl
vd diff -f voodu.hcl --detailed-exitcode    # CI: 0=clean, 1=err, 2=changes pending
```

Markers in the output:

- `~ kind/scope/name` — exists, spec would change (one line per differing field)
- `+ kind/scope/name (new)` — would be created
- `= kind/scope/name (unchanged)` — already in sync
- `--- Would prune ---` — would be deleted (only shown with `--prune`)

## `vd delete` — remove resources

Five shapes, in order of how often you'll reach for them:

```sh
vd delete -f voodu.hcl                       # everything declared in the manifest
vd delete clowk-lp/web                       # one resource (auto-resolves kind)
vd delete deployment/clowk-lp/web            # one resource, explicit kind
vd delete clowk-lp                           # entire scope
vd delete statefulset/data/pg.0              # single pod by ordinal
```

For statefulsets, `--prune` also wipes the underlying volumes:

```sh
vd delete statefulset/data/pg --prune
```

Without `--prune`, volumes stay — you can recreate the pod later and the data is still there.

## File extensions

All of these parse as HCL (or YAML with the same schema). Accepted: `.hcl`, `.voodu`, `.vdu`, `.vd`, `.yml`, `.yaml`.

`vd apply -f web` resolves bare names against these extensions in order.
