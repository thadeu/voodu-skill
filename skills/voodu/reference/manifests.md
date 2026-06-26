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

Root: `image`, `replicas`, `command`, `env`, `env_file`, `env_from`, `ports`, `volumes`, `network`, `networks`, `network_mode`, `restart`, `health_check`, `post_deploy`, `keep_releases`, `extra_hosts`, `cap_add`, `ulimits`, `docker_options`.

Blocks: `build`, `release`, `depends_on`, `resources`, `logs`, `probes`, `autoscale`, `on_deploy`, `on_probe`, `init "<name>"` (repeatable).

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

### Raw docker pass-throughs (`ulimits`, `docker_options`)

Two escape hatches for shapes the typed surface doesn't model. Available on every container-spawning kind: `deployment`, `statefulset`, `job`, `cronjob`, `app`, and per-init under `init {}`. Plugin kinds (`postgres`, `redis`, `mongo`, `caddy`, …) accept the fields at the HCL surface (plugin blocks are schema-free); whether the plugin forwards them to the emitted deployment/statefulset depends on the plugin. If your plugin doesn't pass them through yet, drop down to plain `statefulset {}`.

```hcl
deployment "prod" "search" {
  image = "ghcr.io/acme/search:1.0"

  ulimits = {
    nofile  = "1048576:1048576"   # overrides platform default 65536:65536
    memlock = "-1"                 # new key (no platform default)
    // nproc not declared → keeps platform default 4096:4096
  }

  docker_options = [
    "--shm-size=2g",
    "--sysctl=net.core.somaxconn=4096",
    "--pids-limit=4096",
    "--device=/dev/snd",
  ]
}
```

**`ulimits = {}`** — `map[string]string`. Each entry → one `--ulimit <key>=<value>` flag. Per-key override of voodu's platform defaults (`nofile=65536:65536`, `nproc=4096:4096`); keys the operator doesn't declare stay on the default. Values flow verbatim — docker accepts `"N"` and `"soft:hard"` shapes. No name validation.

**`docker_options = []`** — `list(string)`. Each entry appended verbatim to `docker run` between voodu's managed flags and the image. No parsing, no validation. Use for `--shm-size`, `--pids-limit`, `--sysctl`, `--device`, `--privileged`, `--cap-drop`, `--read-only`, anything docker accepts.

**Footgun:** do NOT redeclare flags voodu already manages — docker rejects duplicates at create time. Managed: `--name`, `--network`, `--restart`, `--env-file`, `--cpus`, `--memory`, `--ulimit`, `--label`, `--add-host`, `--cap-add`, `--log-opt`.

**Hash semantics:** both fields fold into the deployment/statefulset spec hash, so editing either triggers a rolling restart (docker freezes the flags at create time and would otherwise silently keep the old values). Jobs/cronjobs read the spec fresh per run, no hash needed.

**Inside `init {}`:** per-init `ulimits` / `docker_options` REPLACE the parent's at that init's docker-run (whole field replacement, not per-key merge).

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

Best-effort notification webhooks invoked at the end of every rolling restart. Two slots (`success` / `failure`); each slot accepts **zero, one, or many** target blocks. Each target carries `url` + optional `method` / `headers` / `body` (inline) / `file` (asset-backed template).

Multiple blocks per slot fire in **parallel goroutines** with **independent retry budgets** — a slow PagerDuty doesn't delay Slack.

Single target per slot — common case:

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

Multi-target fan-out — declare more blocks per slot:

```hcl
deployment "prod" "api" {
  on_deploy {
    # Success → Slack + Datadog + internal status bot
    success { url = "${SLACK_WEBHOOK_URL}" }
    success {
      url     = "https://api.datadoghq.com/api/v1/events"
      headers = { "DD-API-KEY" = "${DD_API_KEY}" }
    }
    success { url = "https://status.example.com/internal/deploys" }

    # Failure → PagerDuty + OpsGenie (different on-call rotations)
    failure {
      url     = "https://events.pagerduty.com/v2/enqueue"
      headers = { "X-Routing-Key" = "${PD_ROUTING_KEY}" }
    }
    failure {
      url     = "https://api.opsgenie.com/v2/alerts"
      headers = { "Authorization" = "GenieKey ${OPSGENIE_KEY}" }
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

**Delivery contract:** best-effort, **per-target**. Each declared block fires in its own goroutine with its own 3 attempts (1s/5s/30s backoff, 10s per-attempt HTTP timeout). A failure on one target does NOT affect the others, and no target failure ever fails the deploy. Voodu logs drops with `target=<i>/<total>` identity when multiple targets exist. Not in the spec hash (rotating webhook URLs doesn't churn replicas).

**Validation errors** include the index when multiple targets are declared (`on_deploy.failure[2].url is required`); single-target validation stays terse (`on_deploy.failure.url is required`).

### Runtime-health webhooks (`on_probe`)

Sibling of `on_deploy` — same shape, different vocabulary. Fires on **probe transitions** (liveness, readiness, startup), not on deploy completion. Two slots, both repeatable:

- `failure` — any healthy → unhealthy edge from any of the three probes.
- `recovery` — unhealthy → healthy, **only after a prior failure**.

Works on `deployment`, `statefulset`, and plugin-expanded kinds (`postgres`, `redis`, `mongo`). The controller splices the operator's `on_probe` block through `plugin_expand` onto the resulting statefulset, so plugin authors don't have to teach their HCL surface about it.

Common case — single Telegram bot for failures, silent recoveries:

```hcl
deployment "prod" "api" {
  env_from = ["prod/notifications"]   # TG_TOKEN, TG_CHAT_ID

  probes {
    liveness  { http_get { path = "/healthz" } }
    readiness { http_get { path = "/ready"   } }
  }

  on_probe {
    failure {
      url    = "https://api.telegram.org/bot${TG_TOKEN}/sendMessage"
      method = "POST"

      body = {
        chat_id    = "${TG_CHAT_ID}"
        text       = "🚨 *{{kind}}/{{scope}}/{{name}}* — *{{pod}}* {{probe}} failed: {{reason}}"
        parse_mode = "Markdown"
      }
    }
  }
}
```

Multi-target fan-out — paging PagerDuty + dropping a Slack note:

```hcl
postgres "prod" "db" {
  image    = "postgres:16"
  replicas = 3

  on_probe {
    failure {
      url     = "https://events.pagerduty.com/v2/enqueue"
      headers = { "X-Routing-Key" = "${PD_KEY}" }

      body = {
        routing_key  = "${PD_KEY}"
        event_action = "trigger"
        dedup_key    = "{{transition_id}}"             # ← maps cleanly
        payload = {
          summary  = "{{pod}} {{probe}} failed"
          severity = "error"
          source   = "voodu"
          custom_details = {
            scope  = "{{scope}}"
            reason = "{{reason}}"
          }
        }
      }
    }

    failure  { url = "${SLACK_DB_CRITICAL}" }
    recovery { url = "${SLACK_DB_INFO}" }
  }
}
```

**Tokens** (on_probe extends the on_deploy set):

| token | meaning |
|---|---|
| `{{pod}}` | Full container name (e.g. `prod-api-2`, `data-pg-0`). |
| `{{probe}}` | `liveness` \| `readiness` \| `startup`. |
| `{{transition}}` | `failure` \| `recovery`. |
| `{{reason}}` | Probe `Result.Reason` (`HTTP 503`, `exit code 1`, `connect: connection refused`). |
| `{{transition_id}}` | 12-char sha256 prefix from `(scope, name, pod, probe, to_phase, timestamp_truncated_to_1s)` — deterministic, dedup-friendly. |
| `{{timestamp}}` | RFC3339 wall-clock of the transition. |

The original `{{kind}}`, `{{scope}}`, `{{name}}` tokens also resolve. `{{kind}}` is `deployment` for direct kinds and `statefulset` for plugin-expanded ones (postgres / redis / mongo all resolve to `statefulset`).

**Recovery gating state machine.** A `recovery` event fires only when the same runner previously saw a `failure`. A freshly-started pod going healthy on its first sample does NOT fire recovery — that would spam every `vd apply`. After firing recovery, the gate resets: the next recovery requires another failure first. Pairs are clean.

**Suppression during planned teardown.** Rolling restart, scale-down, and manual `vd restart` mark the per-runner `plannedTeardown` flag before stopping the probe runner. Any transition observed AFTER the flag is set is suppressed — operators don't get phantom failure alerts during graceful shutdowns.

**Idempotency** belt-and-suspenders:

- `{{transition_id}}` is deterministic from inputs (1-second time truncation). Receiver dedups on it.
- In-firer 60s TTL cache drops same-id repeats on the controller side (defends against probe-event races during controller restart).

**Best-effort delivery, per-target.** Same retry contract as `on_deploy`: 3 attempts, `[1s, 5s, 30s]` backoff, 10s per HTTP attempt, 2-min overall per goroutine. Failure to deliver never affects container state. NOT folded into the spec hash — URL rotation doesn't trigger a rolling restart.

**Per-pod, not per-resource.** Each replica's transition fires its own webhook. A 5-replica deployment going down fires 5 `failure` events (one per pod). Receivers can aggregate on their side or use `{{transition_id}}` to dedupe.

**Validation errors** include the on_probe block label so operators can locate the offending slot (`on_probe.failure[1].url is required`, `on_probe.recovery.method must be one of POST/PUT/PATCH/DELETE`).

**Not on `job` / `cronjob`.** Those have completion semantics, not runtime-health probes. Use the workload's exit code for completion notifications.

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
- **`{{field}}`** — fire-time, controller-side. Inside webhook body templates (inline `body = { ... }` or asset-backed `file = "${asset…}"`). Substitutes against the live context. Token set differs by hook:
  - `on_deploy`: `{{name}}` `{{status}}` `{{error}}` `{{release_id}}` `{{image}}` `{{started_at}}` `{{completed_at}}` `{{kind}}` `{{scope}}`.
  - `on_probe`: above (without release fields) + `{{pod}}` `{{probe}}` `{{transition}}` `{{reason}}` `{{transition_id}}` `{{timestamp}}`.
  Unknown `{{…}}` tokens are left literal — receivers using handlebars-style templates in their payload aren't broken.

Source helpers (HCL functions, asset-block only):

- `file("./path")` — read local file at apply time, relative to CLI CWD.
- `url("https://...")` — fetched server-side at reconcile time, cached by ETag.
