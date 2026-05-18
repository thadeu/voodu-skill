---
description: HCL manifest reference — every kind voodu accepts
---

Display the following cheat sheet to the user, verbatim, as markdown.

# voodu HCL manifests — every kind

Scoped kinds take **two labels**: `<scope>` `<name>`.

## `deployment` — stateless replicas

```hcl
deployment "clowk" "api" {
  image    = "ghcr.io/clowk/api:1.2.3"   # or omit for build-mode
  replicas = 2
  ports    = ["8080"]

  env = { PORT = "8080" }

  restart      = "always"                # always | on-failure | no
  health_check = "/healthz"
}
```

Build-mode (no `image`): set `path = "."` and a `lang { name = ... }` block.

Fields: `image`, `path`, `workdir`, `dockerfile`, `replicas`, `command`, `env`, `env_file`, `ports`, `volumes`, `network`, `networks`, `network_mode`, `restart`, `health_check`, `post_deploy`, `keep_releases`, `extra_hosts`, `cap_add`, `build_args`. Blocks: `lang`, `release`, `depends_on`, `resources`.

## `statefulset` — stateful, identity-stable

```hcl
statefulset "data" "pg" {
  image    = "postgres:15-alpine"
  replicas = 1
  ports    = ["5432"]

  env = { POSTGRES_DB = "myapp" }

  volume_claim "data" {
    mount_path = "/var/lib/postgresql/data"
  }
}
```

DNS: `pg-0.data`, `pg-1.data` (per-pod), `pg.data` (round-robin). Volumes survive restart and rebuild.

## `ingress` — host + TLS

```hcl
ingress "clowk" "api" {
  host = "api.clowk.in"

  tls {
    enabled  = true
    provider = "letsencrypt"   # letsencrypt | internal | (none)
    email    = "ops@clowk.in"
  }

  # path-based routing (optional)
  location { path = "/api/v1" }
  location { path = "/api/v2" strip = true }
}
```

`service` defaults to the ingress name; set it explicitly for cross-app routing.

## `app` — sugar for deployment + ingress

```hcl
app "myapp" "web" {
  image    = "ghcr.io/me/myapp:latest"
  replicas = 3
  ports    = ["8080"]

  env = { PORT = "8080" }

  host = "myapp.example.com"

  tls {
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@example.com"
  }
}
```

## `job` — manual one-shot

```hcl
job "clowk-lp" "migrate" {
  image    = "ghcr.io/clowk/lp:latest"
  command  = ["rails", "db:migrate"]
  env_from = ["clowk-lp/web"]
  timeout  = "10m"
}
```

Triggered by: `vd run clowk-lp/migrate`.

## `cronjob` — scheduled

```hcl
cronjob "clowk-lp" "nightly" {
  schedule = "0 3 * * *"
  timezone = "America/Sao_Paulo"

  image   = "ghcr.io/clowk/lp:latest"
  command = ["rake", "backup:run"]

  env_from = ["clowk-lp/web"]

  concurrency_policy        = "Forbid"   # Allow | Forbid | Replace
  successful_history_limit  = 3
  failed_history_limit      = 5
}
```

## `asset` — file bundles

```hcl
asset "data" "pg-config" {
  postgresql_conf = file("./configs/postgresql.conf")
  pg_hba_conf     = file("./configs/pg_hba.conf")
}

statefulset "data" "pg" {
  image = "postgres:15-alpine"

  volumes = [
    "${asset.data.pg-config.postgresql_conf}:/etc/postgresql/postgresql.conf:ro",
  ]
}
```

Sources: `file("./path")` (local), `url("https://...")` (remote, cached by ETag), `"literal string"`.

Refs:
- `${asset.scope.name.key}` — four-segment, scoped
- `${asset.name.key}` — three-segment, unscoped (one-label `asset "name" { ... }`)

## Macros: `postgres`, `redis`, `mongo`

```hcl
postgres "data" "pg" {
  plugin { version = "0.2.0" }
  image  = "postgres:15-alpine"
}

redis "data" "cache" {
  plugin { version = "latest" }
  image  = "redis:8"
}
```

Server-side expansion into a `statefulset`. Operator fields win over plugin defaults.

## Resources block (CPU / memory)

```hcl
deployment "clowk" "api" {
  image = "..."

  resources {
    limits {
      cpu    = "2"          # or "500m"
      memory = "1Gi"        # or "512Mi", "2G", plain bytes
    }
  }
}
```

Works on `deployment`, `statefulset`, `job`, `cronjob`.

## Interpolation

- `${VAR}` / `${VAR:-default}` — shell env (CLI-side)
- `${asset.scope.name.key}` — asset bind mount path
- `file("./path")` — local file, read at apply time
- `url("https://...")` — remote, fetched server-side
