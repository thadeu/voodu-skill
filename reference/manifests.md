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

Root: `image`, `replicas`, `command`, `env`, `env_file`, `env_from`, `ports`, `volumes`, `network`, `networks`, `network_mode`, `restart`, `health_check`, `post_deploy`, `keep_releases`, `extra_hosts`, `cap_add`.

Blocks: `build`, `release`, `depends_on`, `resources`, `logs`, `probes`, `autoscale`, `on_deploy`, `init "<name>"` (repeatable).

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

### Probes (kubelet-style health checks)

Three independent probes per pod. All three sub-blocks are optional. Each takes exactly one selector (`http_get` / `tcp_socket` / `exec`) plus optional timing knobs.

```hcl
deployment "prod" "api" {
  image = "ghcr.io/acme/api:1.4"

  probes {
    # Boot-grace window. Pod is NOT ready until startup passes
    # once. After that the runner self-stops and readiness takes
    # over. Use for slow-boot apps (Rails ~30s, JVM, bootsnap cold).
    startup {
      http_get { path = "/health" port = 3000 }
      period            = "2s"
      failure_threshold = 30        # 60s window
      success_threshold = 1
    }

    # Failure threshold → docker restart (in-place, same volumes).
    liveness {
      http_get { path = "/health" port = 3000 }
      period            = "10s"
      failure_threshold = 3
    }

    # Phase transitions → flips the pod's ready bit in
    # DeploymentStatus.ReplicaReadiness; caddy active health check
    # automatically bypasses unready upstreams.
    readiness {
      http_get { path = "/ready" port = 3000 }
      period            = "5s"
      failure_threshold = 1
      success_threshold = 2
    }
  }
}
```

**Selectors (one per probe):**

```hcl
http_get { path = "/healthz" port = 8080 scheme = "https" http_headers = { "X-Probe" = "voodu" } }
tcp_socket { port = 6379 }
exec { command = ["pg_isready", "-U", "postgres"] }
```

**Knobs:** `initial_delay`, `period`, `timeout`, `failure_threshold`, `success_threshold` (durations as strings: `"5s"`, `"1m30s"`).

**Auto caddy ingress gating:** when a deployment declares an HTTP readiness probe, the controller automatically points caddy's active health check at the readiness path. No `health_check =` / `lb { interval = ... }` needed on the ingress side — voodu derives both from the probe block.

**Operator UX:** `vd describe deployment <ref>` shows per-replica readiness:

```
readiness:
  prod-api.a3f9   ready=true   phase=healthy
  prod-api.b1c2   ready=false  startup=waiting  phase=unhealthy  reason="GET /ready → 502"
```

Also available on `app` and `statefulset` (M1.3). Postgres and redis plugins ship sensible default probes already wired — see [plugins.md](plugins.md).

### Init containers

Ordered one-shot containers that run sequentially before the main container of each replica. Each must exit 0 before the next runs. Inherits env / env_from / volumes / networks / extra_hosts / cap_add from the parent.

```hcl
deployment "prod" "api" {
  image = "ghcr.io/acme/api:1.4"

  init "validate-config" {
    command = ["bin/config-check"]
    timeout = "30s"
    retries = 0
  }

  init "migrate" {
    command = ["bin/rails", "db:migrate"]
    timeout = "10m"
    retries = 1
  }

  init "warm-cache" {
    command = ["bin/warm-cache"]
    timeout = "5m"

    resources {
      limits { cpu = "2" memory = "1Gi" }   # per-init override
    }
  }
}
```

**Fields:** `image` (defaults to parent's image), `command` (required), `timeout` (default `"10m"`), `retries` (default 0, capped at 5), `resources { limits { cpu memory } }`.

**Failure:** the failing init container is LEFT IN PLACE so the operator can `docker logs <container-name>`. Surfaces in `vd describe`:

```
init failures (recent):
  a3f9   init=migrate   exit=1   attempts=3   2m   container exited 1: PG::Error
```

The HCL keyword is `init` (no `_container` suffix — voodu's manifest layer talks about pods, not containers). Internally it's still a k8s "init container" pattern.

### Autoscale (CPU-based horizontal scaling)

Mutually exclusive with `replicas = N` — operator picks one. The autoscaler loop reads CPU% via the same StatsCollector that powers `vd stats` and adjusts replica count within the declared bounds.

```hcl
deployment "prod" "api" {
  image = "ghcr.io/acme/api:1.4"

  autoscale {
    min        = 3       # baseline + spare for rolling restart
    max        = 15      # ceiling (host-protection)
    cpu_target = 60      # mean CPU% the autoscaler tries to hold

    # Asymmetric cooldowns ("respond fast, retreat slowly"):
    # scale-up is cheap to undo; scale-down can cause 503s under
    # bursty traffic, so default 30s up / 5m down.
    cooldown_up   = "15s"   # default 30s
    cooldown_down = "10m"   # default 5m
  }
}
```

**Decision band (hysteresis):** mean CPU > target × 1.1 → scale up by 1. Mean CPU < target × 0.7 → scale down by 1. In between → hold. The wide deadband dampens thrash.

**Typical patterns:**

- Worker / sidekiq: `min = 2`, `max = 20`, `cpu_target = 70`, tight cooldowns (`15s` / `2m`) — queue depth changes fast.
- Web / HTTP: `min = 3`, `max = 15`, `cpu_target = 60`, generous `cooldown_down = "10m"` — don't collapse capacity during a campaign lull.

### Post-deploy webhooks (`on_deploy`)

Best-effort notification webhooks invoked at the end of every rolling restart. Two sub-blocks (`success` / `failure`); declare either or both. Each carries `url` + optional `method` / `headers` / `body` (inline) / `file` (asset-backed template).

```hcl
deployment "prod" "api" {
  on_deploy {
    success {
      url = "${SLACK_WEBHOOK_URL}"   # default voodu payload
    }

    failure {
      url    = "https://events.pagerduty.com/v2/enqueue"
      method = "POST"                # default; whitelist: POST/PUT/PATCH/DELETE

      headers = {
        "Content-Type"  = "application/json"
        "X-Routing-Key" = "${PD_ROUTING_KEY}"
      }

      # Asset-backed body template — keep complex JSON out of HCL.
      file = "${asset.prod.webhooks.pagerduty_event}"
    }
  }
}
```

**Body shapes** (mutex):

- `body = { ... }` — inline HCL object literal. For ≤ a few flat fields (e.g. Telegram bot `{chat_id, text, parse_mode}`).
- `file = "${asset.X.Y.key}"` — asset reference to a JSON template file. For ≥ 5 lines of nested JSON (Slack Block Kit, PagerDuty Events v2). Bare paths rejected — must be an asset ref.
- Neither declared → voodu sends the default `WebhookPayload` (kind, scope, name, release_id, image, status, started_at, completed_at, error).

**Body interpolation** (two contexts):

| token | resolves | when |
|---|---|---|
| `${VAR}` | shell env + env_from'd buckets | parse-time, client-side |
| `{{field}}` | release context | fire-time, controller-side |

Allowed `{{...}}`: `{{kind}}` `{{scope}}` `{{name}}` `{{release_id}}` `{{image}}` `{{status}}` `{{error}}` `{{started_at}}` `{{completed_at}}`. Unknown `{{...}}` tokens are left literal (some receivers use handlebars-style themselves).

**Headers:** operator's headers stack on top of voodu's default `Content-Type: application/json`. `User-Agent` is force-set to `voodu-deploy-webhook` — operator override is ignored (source-of-call debug signal).

**Delivery contract:** 3 attempts, 1s/5s backoff, 10s per-attempt HTTP timeout. Failure to deliver does NOT fail the deploy — voodu logs and moves on. Not in the spec hash (rotating webhook URLs doesn't churn replicas).

### Logs (docker log driver cap)

```hcl
deployment "prod" "api" {
  logs {
    max_size  = "100m"   # default "10m"
    max_files = 5        # default 3
  }
}
```

Caps the `json-file` driver per container. Default (10m × 3) is platform-applied even when the block is omitted, so a runaway container can't fill the host disk silently.

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

## `registry` — private image pull credentials

Host-wide (NOT scoped — one label). Voodu rebuilds `~/.docker/config.json` atomically on every apply or delete of a registry resource, so subsequent `docker pull` calls authenticate without a manual `docker login`.

```hcl
registry "ghcr" {
  url      = "ghcr.io"
  username = "${GHCR_USER}"
  token    = "${GHCR_TOKEN}"   # `password = "..."` is accepted as an alias
}

# Then any deployment on the host can pull from ghcr.io transparently:
deployment "prod" "api" {
  image = "ghcr.io/acme/private-api:1.4"
  # no registry config here — auth lives in ~/.docker/config.json
}
```

**One-credential-per-host:** `~/.docker/config.json` is singular. Every `vd apply` rewrites the entry — the active credential is whoever applied last. **Use a service account / bot token**, not per-dev personal PATs (per-dev tokens trample each other). Distribute the bot token via gitignored `.envrc` + direnv (or your team's password manager).

**No `env_from` on `registry`** — secrets stay in shell env. The registry kind is the one place where bucket-fed `${VAR}` doesn't work; the recommended team workflow is a `.envrc` template stored in the repo with the shared service-account token.

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

Three different interpolation contexts, resolved at different stages:

- **`${VAR}` or `${VAR:-default}`** — parse-time, CLI-side. Resolves from the operator's shell env **plus** any `env_from`'d config buckets the resource declares. Shell wins over bucket on collision (ad-hoc override). Works in any string field.
- **`${asset.scope.name.key}` / `${asset.name.key}`** — apply-time, controller-side. Rewrites to the materialised host path of the asset. Used in volumes, body templates, etc.
- **`{{field}}`** — fire-time, controller-side. Only inside `on_deploy` body templates (inline or file). Substitutes against the release context (`{{name}}`, `{{status}}`, `{{error}}`, `{{release_id}}`, `{{image}}`, `{{started_at}}`, `{{completed_at}}`, `{{kind}}`, `{{scope}}`).

Source helpers (HCL functions, asset-block only):

- `file("./path")` — read local file at apply time, relative to CLI CWD.
- `url("https://...")` — fetched server-side at reconcile time, cached by ETag.
