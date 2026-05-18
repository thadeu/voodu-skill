# Plugins

Plugins are standalone binaries under `/opt/voodu/plugins`. They add macros (`postgres`, `redis`, ...) or services (ingress).

## Official plugins

| Repo | Purpose | Macro |
|---|---|---|
| `thadeu/voodu-caddy` | Ingress + TLS (Let's Encrypt, wildcard) | reconciles `ingress` |
| `thadeu/voodu-postgres` | Postgres with backup, replica, promote | `postgres` |
| `thadeu/voodu-redis` | Redis with Sentinel HA | `redis` |
| `thadeu/voodu-mongo` | MongoDB | `mongo` |

## Commands

```sh
vd plugins:install thadeu/voodu-caddy        # from GitHub
vd plugins:install thadeu/voodu-postgres
vd plugins:list
vd plugins:update                            # all installed
vd plugins:update voodu-postgres             # one
vd plugins:remove voodu-mongo
```

## Version control from HCL

Every macro accepts a `plugin { ... }` block:

```hcl
postgres "data" "pg" {
  plugin {
    version = "0.2.0"               # specific tag; reinstall on mismatch
    # version = "latest"            # always re-fetch the default branch
    # repo = "myorg/voodu-postgres-fork"   # fork override
  }
  image = "postgres:15-alpine"
}
```

Block omitted = use whatever's installed locally, no network roundtrip.

## Command aliases

Plugins can declare aliases:

```sh
vd pg:psql                # same as `vd postgres:psql`
vd pg:create main
vd pg:promote --replica 1 # promote pg-1 to primary
```

## Postgres — common commands (plugin)

```sh
vd pg:create main                    # create a new database
vd pg:list
vd pg:psql main                      # interactive psql shell
vd pg:backup main                    # snapshot
vd pg:restore main backup-2026-01-01
vd pg:promote --replica 1            # promote pg-1 to primary
vd pg:failover                       # alias of promote
```

## Redis — common commands (plugin)

```sh
vd redis:cli                         # interactive redis-cli
vd redis:failover                    # Sentinel-driven failover
```

## Caddy / ingress — no extra CLI

`voodu-caddy` is purely reactive: declare `ingress { ... }` in HCL, the controller reconciles, Caddy generates the config.

To inspect what Caddy applied:

```sh
vd describe ingress clowk/api
vd logs voodu-caddy                  # reverse-proxy logs
```
