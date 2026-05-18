# HCL manifests — every kind

Scoped kinds take **two labels**: `<scope>` and `<name>`.
Scope groups resources; name is unique within scope.

## `deployment` — stateless replicas

```hcl
deployment "clowk" "api" {
  image    = "ghcr.io/clowk/api:1.2.3"
  replicas = 2
  ports    = ["8080"]

  env = {
    PORT     = "8080"
    NODE_ENV = "production"
  }

  restart      = "always"                # always | on-failure | no
  health_check = "/healthz"              # default "/"
}
```

### Registry mode vs build mode

`image = "..."` and `build { ... }` are **mutually exclusive** (parse error if both):

- **Registry mode** — `image = "ghcr.io/..."`. Controller pulls and runs. CI publishes the image.
- **Build mode** — `build { ... }` block. CLI tarballs the working tree, server runs `docker build`, tags `<scope>-<name>:latest` for the workload to pull.

```hcl
deployment "clowk" "api" {
  replicas = 2
  ports    = ["8080"]

  build {
    context    = "."                     # docker build context, default "."
    dockerfile = "Dockerfile"            # default name inside context
    path       = "cmd/api"               # voodu-only: used by auto-generated Dockerfiles (Go: `go build ./<path>`)
    args = {
      NODE_VERSION = "24-alpine"         # docker --build-arg
    }

    lang {
      name    = "bun"                    # go | ruby | rails | python | nodejs | bun | ...
      version = "1.1"
    }
  }
}
```

**Auto-detect** (omit both `image` and `build {}`): `vd apply` builds the repo root and auto-detects the runtime from marker files (`go.mod`, `Gemfile`, `package.json`, …). Generates a Dockerfile if your repo doesn't ship one. Equivalent to `build { context = "." }` plus auto-detected lang.

```hcl
deployment "demo" "web" {}   # implicit build mode at repo root
```

The tarball follows docker-build semantics: `.dockerignore` controls inclusion if present, otherwise `.gitignore`. Uncommitted changes ship — working tree, not git HEAD.

### Available fields

Root: `image`, `replicas`, `command`, `env`, `env_file`, `env_from`, `ports`, `volumes`, `network`, `networks`, `network_mode`, `restart`, `health_check`, `post_deploy`, `keep_releases`, `extra_hosts`, `cap_add`. Blocks: `build`, `release`, `depends_on`, `resources`.

Inside `build { ... }`: `context`, `dockerfile`, `path`, `args`, plus nested `lang { name, version, entrypoint }`.

### Ports — loopback-only by default

`ports = ["8080"]` maps to `127.0.0.1:8080`. To expose publicly, declare the IP explicitly:

```hcl
ports = ["0.0.0.0:8080:8080"]
```

In practice, public exposure goes through an **ingress**, not the deployment.

### Resources (CPU/memory, k8s-style)

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

### Release phase (pre/post deploy)

```hcl
deployment "clowk" "api" {
  release {
    pre_command  = ["rails", "db:migrate"]
    command      = ["rails", "release:tasks"]
    post_command = ["rails", "cache:clear"]
    timeout      = "5m"
  }
}
```

## `statefulset` — stateful, identity-stable pods

```hcl
statefulset "data" "pg" {
  image    = "postgres:15-alpine"
  replicas = 1
  ports    = ["5432"]

  env = {
    POSTGRES_DB = "myapp"
    PGDATA      = "/var/lib/postgresql/data/pgdata"
    # passwords never in HCL — use `vd config set`
  }

  volume_claim "data" {
    mount_path = "/var/lib/postgresql/data"
  }
}
```

How it differs from `deployment`:

- Pods have stable DNS: `pg-0.data`, `pg-1.data` (plus the round-robin `pg.data`).
- Each ordinal owns its own Docker volume (`voodu-data-pg-data-0`, ...).
- Volumes survive restart and rebuild. They go away only with `vd delete ... --prune`.

## `ingress` — host routing + TLS

```hcl
ingress "clowk" "api" {
  host = "api.clowk.in"
  port = 8080              # optional if the deployment already declares one

  tls {
    email = "ops@clowk.in"   # enabled = true and provider = "letsencrypt" are the defaults
  }
}
```

`service` defaults to the ingress name. Cross-app routing:

```hcl
ingress "public" "api_http" {
  host    = "api.internal"
  service = "api"          # points at deployment "public" "api"
  port    = 3000
}
```

### TLS — block-present = on

Declaring `tls {}` (even bare) flips `enabled = true` and `provider = "letsencrypt"` by default. To **disable** TLS for an ingress, omit the entire block. To override the issuer (dev/staging), set `provider = "internal"`. An explicit `enabled = false` inside the block IS honoured — escape hatch for keeping the block declared while toggling TLS off.

### Four TLS profiles (provided by voodu-caddy)

```hcl
# HTTP only — no TLS block at all
ingress "x" "http" { host = "api.local"; service = "api" }

# Let's Encrypt (default — HTTP-01, finite known hosts, no wildcards)
tls { email = "ops@x.com" }

# Internal CA (Caddy self-signed) — dev / staging
tls { provider = "internal" }

# On-demand wildcard (the only profile that supports *.domain)
tls {
  email     = "ssl@x.com"
  on_demand = true
  ask       = "http://app:3000/internal/allow_domain"   # REQUIRED
}
```

### Path-based routing

```hcl
ingress "acme" "api" {
  host = "api.example.com"

  location { path = "/api/v1" }
  location { path = "/api/v2" }
}
```

Strip prefix before forwarding upstream:

```hcl
location {
  path  = "/docs/voodu"
  strip = true             # backend sees /getting-started
}
```

## `app` — sugar for deployment + ingress

```hcl
app "myapp" "web" {
  image    = "ghcr.io/myorg/myapp:latest"
  replicas = 3
  ports    = ["8080"]

  env = { PORT = "8080" }

  health_check = "/healthz"

  # ingress side
  host = "myapp.example.com"

  tls {
    email = "ops@example.com"
  }
}
```

Expands server-side into a `deployment` + `ingress` pair with the same `(scope, name)`.

## `job` — manual one-shot

```hcl
job "clowk-lp" "migrate" {
  image = "ghcr.io/clowk/lp:latest"

  command = ["rails", "db:migrate"]

  env      = { RAILS_ENV = "production" }
  env_from = ["clowk-lp/web"]    # inherit config bucket from the web deployment

  timeout = "10m"
}
```

Runs only when you call: `vd run clowk-lp/migrate`.

## `cronjob` — scheduled job

```hcl
cronjob "clowk-lp" "nightly-backup" {
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

## `asset` — declarative file bundles

Materialise files on the host so other resources can mount them:

```hcl
asset "data" "redis-config" {
  configuration = file("./configs/redis.conf")        # local, read at apply time
  acl_users     = url("https://r2.example.com/acl")   # remote, fetched server-side
  motd          = "Welcome to redis"                  # inline literal
}

statefulset "data" "cache" {
  image   = "redis:8"
  command = ["redis-server", "/etc/redis/redis.conf"]

  volumes = [
    "${asset.data.redis-config.configuration}:/etc/redis/redis.conf:ro",
    "${asset.data.redis-config.acl_users}:/etc/redis/users.acl:ro",
  ]
}
```

- **Scoped** (`asset "scope" "name"`): four-segment ref `${asset.scope.name.key}`.
- **Unscoped** (`asset "name"`): three-segment ref `${asset.name.key}` — handy for shared bytes (CA bundles, common ACLs).

Edit the local file → re-apply → asset hash changes → automatic rolling restart.

## Macros (postgres, redis, mongo) — plugin-provided

```hcl
postgres "data" "pg" {
  plugin { version = "0.2.0" }      # or "latest"
  image  = "postgres:15-alpine"
}

redis "data" "cache" {
  plugin { version = "latest" }
  image  = "redis:8"
}
```

Server-side expansion into a `statefulset`. Plugin fills defaults; anything you declare wins.

## Interpolation

- `${VAR}` or `${VAR:-default}` — shell env (resolved CLI-side).
- `${asset.scope.name.key}` — asset bind mount path.
- `file("./path")` — read at apply time, relative to the CLI's CWD.
- `url("https://...")` — fetched server-side, cached by ETag.
