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

## Default probes (postgres ≥ 0.13.0, redis ≥ 0.14.0)

Both plugins ship sensible kubelet-style probe sets out of the box so a bare block delivers production-ready health checks:

```hcl
postgres "data" "pg" {}    # tcp_socket liveness on 5432, pg_isready readiness
redis    "data" "cache" {} # tcp_socket liveness on 6379, redis-cli ping readiness
```

| plugin | liveness | readiness |
|---|---|---|
| postgres | `tcp_socket { port = <spec.port> }` w/ `initial_delay = "20s"` | `exec { command = ["pg_isready", "-U", "<spec.user>", "-d", "<spec.database>", "-p", "<spec.port>"] }` |
| redis | `tcp_socket { port = 6379 }` | `exec { command = ["redis-cli", "ping"] }` |

**Override = total replacement.** Declaring any `probes { ... }` block in the HCL replaces the default entirely (no sub-block merging — operator-declared partial probes do NOT inherit the plugin's defaults for the slots they didn't declare). To override one and keep the other, redeclare both. To disable probes, declare `probes {}` empty.

```hcl
# Replace BOTH (lose default readiness):
redis "data" "cache" {
  probes {
    liveness { http_get { path = "/metrics" port = 9121 } }
    # default readiness is gone — redeclare if you still want it:
    readiness {
      exec { command = ["redis-cli", "ping"] }
      period            = "5s"
      success_threshold = 2
    }
  }
}
```

**Authenticated redis:** if `requirepass` is set, pass the password:

```hcl
redis "data" "cache" {
  probes {
    readiness {
      exec {
        command = ["redis-cli", "-a", "$REDIS_PASSWORD", "--no-auth-warning", "ping"]
      }
      period            = "5s"
      success_threshold = 2
    }
  }
}
```

`$REDIS_PASSWORD` is read from the container's env at probe-exec time (same env the operator wires via `env_from` / `vd config set`).

**Upgrade note:** the first `vd apply` after upgrading to a plugin version that ships defaults flips the spec hash → one cosmetic rolling restart (top-down per ordinal for statefulsets). Per-pod volume claims survive.

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
