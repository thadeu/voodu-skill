# apply / diff / delete

## `vd apply` — apply a manifest

```sh
vd apply -f voodu.hcl                          # single file
vd apply -f deployments.hcl -f ingresses.hcl   # multiple -f
vd apply -f ./manifests/                       # directory (every .hcl/.voodu/.vdu/.vd)
vd apply -f web                                # bare name resolves web.voodu/.hcl/.vdu/.vd
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

`${VAR}` and `${VAR:-default}` are resolved **on your machine** before the tarball ships. The interpolation context combines:

1. The operator's shell env (`os.Environ()`).
2. Any `env_from`'d config bucket the resource declares — the CLI fetches the bucket from the controller before parsing, so `${SLACK_WEBHOOK_URL}` in `on_deploy.success.url` can come from `vd config set -s prod -n shared SLACK_WEBHOOK_URL=...`.

Shell wins over bucket on collision (ad-hoc override for testing: `SLACK_WEBHOOK_URL=https://test/h vd apply ...`).

```hcl
deployment "clowk-lp" "web" {
  env_from = ["clowk-lp/shared"]              # bucket lookup at parse-time

  image = "ghcr.io/clowk/lp:${IMAGE_TAG:-latest}"

  on_deploy {
    success {
      url = "${SLACK_WEBHOOK_URL}"            # resolved from clowk-lp/shared
    }
  }
}
```

```sh
vd config set -s clowk-lp -n shared SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
IMAGE_TAG=v1.4.2 vd apply -f voodu.hcl -r prod
```

**Caveat:** the parse-time bucket lookup runs for **local applies only** (no `-r`). With `-r <remote>`, the SSH-forward path keeps shell-only interpolation — fall back to direnv / shell exports there.

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

All accepted extensions parse as HCL: `.hcl`, `.voodu`, `.vdu`, `.vd`. YAML input was removed in beta — see [reference/manifests.md](manifests.md) for why HCL became the only input format.

`vd apply -f web` resolves bare names against these extensions in order.
