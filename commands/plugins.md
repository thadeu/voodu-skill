---
description: vd plugins — install, list, update, remove plugins
---

Display the following cheat sheet to the user, verbatim, as markdown.

# `vd plugins` — manage plugins

Plugins are standalone binaries under `/opt/voodu/plugins`. They add macros (`postgres`, `redis`, ...) or services (ingress).

## Commands

```sh
vd plugins:install thadeu/voodu-caddy        # install from GitHub
vd plugins:install thadeu/voodu-postgres
vd plugins:list
vd plugins:update                            # update all installed
vd plugins:update voodu-postgres             # update one
vd plugins:remove voodu-mongo
```

## Official plugins

| Repo | Purpose | Macro |
|---|---|---|
| `thadeu/voodu-caddy` | Ingress + TLS (Let's Encrypt, wildcard) | reconciles `ingress` |
| `thadeu/voodu-postgres` | Postgres with backup, replica, promote | `postgres` |
| `thadeu/voodu-redis` | Redis with Sentinel HA | `redis` |
| `thadeu/voodu-mongo` | MongoDB | `mongo` |

## Version control from HCL

```hcl
postgres "data" "pg" {
  plugin {
    version = "0.2.0"               # specific tag; reinstalls on mismatch
    # version = "latest"            # always re-fetch the default branch
    # repo = "myorg/voodu-postgres-fork"   # fork override
  }
  image = "postgres:15-alpine"
}
```

Block omitted = use whatever's installed locally, no network roundtrip.

## Plugin sub-commands (aliases)

Plugins declare command aliases. For postgres (alias `pg`):

```sh
vd pg:create main                    # create a database
vd pg:list
vd pg:psql main                      # interactive psql shell
vd pg:backup main
vd pg:restore main backup-2026-01-01
vd pg:promote --replica 1            # promote pg-1 to primary
```

For redis:

```sh
vd redis:cli
vd redis:failover
```

For caddy (no extra CLI — purely reactive to `ingress` manifests):

```sh
vd describe ingress clowk/api
vd logs voodu-caddy
```
