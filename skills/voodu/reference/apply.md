# `vd apply` — apply HCL manifests

```sh
vd apply -f voodu.hcl                          # single file
vd apply -f deployments.hcl -f ingresses.hcl   # multiple -f
vd apply -f ./manifests/                       # directory (every .hcl/.voodu/.vdu/.vd)
vd apply -f web                                # bare name resolves web.voodu/.hcl/.vdu/.vd
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

`${VAR}` and `${VAR:-default}` are resolved on **your machine** before the tarball ships. The interpolation context includes:

1. Your shell env (`os.Environ()`).
2. `env_from`'d config buckets — the CLI fetches them before parsing, so `${SLACK_WEBHOOK_URL}` in `on_deploy.success.url` can come from `vd config set -s prod -n shared SLACK_WEBHOOK_URL=...`. Shell wins on collision (ad-hoc override).

```hcl
deployment "clowk-lp" "web" {
  env_from = ["clowk-lp/shared"]                # bucket → ${VAR} at parse time

  image = "ghcr.io/clowk/lp:${IMAGE_TAG:-latest}"

  on_deploy {
    success { url = "${SLACK_WEBHOOK_URL}" }    # from clowk-lp/shared
  }
}
```

```sh
IMAGE_TAG=v1.4.2 vd apply -f voodu.hcl -r prod
```

**Caveat:** bucket-fed interpolation is **local-apply only**. With `-r <remote>` the SSH-forward path keeps shell-only — use direnv / shell exports for remote applies.

## File extensions

All parse as HCL: `.hcl`, `.voodu`, `.vdu`, `.vd`. YAML input was removed in beta — HCL is the only accepted format.

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
