# Ready-to-paste examples

## Simple app (deployment + ingress + TLS)

```hcl
# voodu.hcl
app "myapp" "web" {
  image    = "ghcr.io/me/myapp:latest"
  replicas = 2
  ports    = ["8080"]

  env = { PORT = "8080" }

  health_check = "/healthz"

  host = "myapp.example.com"

  tls {
    email = "ops@example.com"   # `enabled = true` and `provider = "letsencrypt"` are the defaults
  }
}
```

```sh
vd apply -f voodu.hcl
```

**Note on TLS defaults:** declaring `tls {}` at all flips `enabled = true` and `provider = "letsencrypt"` automatically. The example above only writes `email` — the two fields below are redundant unless you want to override:

```hcl
tls {
  enabled  = true              # default when block is present
  provider = "letsencrypt"     # default issuer
  email    = "ops@example.com"
}
```

Override `provider = "internal"` for dev/staging self-signed (no public DNS needed). Omit the entire `tls {}` block to disable TLS.

## Build-mode app (no pre-built image)

```hcl
deployment "clowk" "api" {
  replicas = 2
  ports    = ["8080"]

  build {
    context = "."                    # default; can omit
    lang {
      name    = "bun"
      version = "1.1"
    }
  }

  health_check = "/healthz"
}

ingress "clowk" "api" {
  host = "api.example.com"

  tls {
    email = "ops@example.com"
  }
}
```

```sh
vd apply -f voodu.hcl   # tarball of build.context → SSH → server-side build
```

For a custom Dockerfile + build args (docker-compose-shaped):

```hcl
deployment "clowk" "api" {
  build {
    context    = "."
    dockerfile = "Dockerfile.api"
    args = {
      BUN_VERSION = "1.1"
      GIT_SHA     = "${GIT_SHA:-dev}"
    }
  }
}
```

For the terse "auto-detect everything" form: `deployment "clowk" "api" {}` — voodu sniffs the runtime from marker files (`go.mod`, `Gemfile`, `package.json`, …) and generates a Dockerfile if your repo doesn't ship one.

## Single-node postgres + app

```hcl
# voodu.hcl
postgres "data" "pg" {
  plugin { version = "0.2.0" }
  image = "postgres:15-alpine"

  env = { POSTGRES_DB = "myapp" PGDATA = "/var/lib/postgresql/data/pgdata" }
}

app "myapp" "web" {
  image    = "ghcr.io/me/myapp:latest"
  replicas = 2
  ports    = ["8080"]

  env = { PORT = "8080" }

  host = "myapp.example.com"

  tls {
    email = "ops@example.com"
  }
}
```

```sh
PG_PASS=$(openssl rand -hex 16)
vd config data/pg set POSTGRES_PASSWORD=$PG_PASS
vd config myapp/web set DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp"
vd apply -f voodu.hcl
```

## S3 backup cronjob

```hcl
cronjob "clowk" "s3-backup" {
  schedule = "0 4 * * *"
  timezone = "America/Sao_Paulo"

  image   = "amazon/aws-cli"
  command = ["s3", "sync", "/data", "s3://backups/clowk"]

  env_from = ["aws/cli"]

  volumes = ["/var/backups/clowk:/data:ro"]

  successful_history_limit = 3
  failed_history_limit     = 5
}
```

```sh
# shared bucket for credentials
vd config aws/cli set \
  AWS_ACCESS_KEY_ID=... \
  AWS_SECRET_ACCESS_KEY=... \
  AWS_REGION=us-east-1

vd apply -f cronjob.hcl

# trigger immediately, bypassing the schedule:
vd run clowk/s3-backup
```

## One-shot migration (`job`)

```hcl
job "clowk-lp" "migrate" {
  image    = "ghcr.io/clowk/lp:latest"
  command  = ["rails", "db:migrate"]

  env_from = ["clowk-lp/web"]    # inherit DATABASE_URL etc from the web deployment
  timeout  = "10m"
}
```

```sh
vd apply -f voodu.hcl
vd run clowk-lp/migrate
vd logs clowk-lp/migrate -f
```

## Versioned API (same host, different paths)

```hcl
deployment "acme" "api-v1" { image = "ghcr.io/acme/api-v1:latest" }
deployment "acme" "api-v2" { image = "ghcr.io/acme/api-v2:latest" }

ingress "acme" "api-v1" {
  host    = "api.example.com"
  service = "api-v1"
  location { path = "/api/v1" }

  tls {
    email = "ops@example.com"
  }
}

ingress "acme" "api-v2" {
  host    = "api.example.com"
  service = "api-v2"
  location { path = "/api/v2" }

  tls {
    email = "ops@example.com"
  }
}
```

## Wildcard multi-tenant (`*.mysaas.io`)

```hcl
ingress "saas" "tenants" {
  host    = "*.mysaas.io"
  service = "app"
  port    = 3000

  tls {
    email     = "ssl@mysaas.io"
    on_demand = true
    ask       = "http://app:3000/internal/allow_domain"
  }
}
```

Your app must serve `GET /internal/allow_domain?domain=foo.mysaas.io` → 200 (allow) or 4xx (deny).

## Full stack: postgres + redis + app + ingress

```hcl
# voodu.hcl
asset "data" "pg-config" {
  postgresql_conf = file("./configs/postgresql.conf")
  pg_hba_conf     = file("./configs/pg_hba.conf")
}

postgres "data" "pg" {
  plugin { version = "0.13.0" }
  image = "postgres:15-alpine"

  # Default probes (tcp_socket liveness + pg_isready readiness)
  # ship for free; only declare `probes { }` here if overriding.

  command = [
    "postgres",
    "-c", "config_file=/etc/postgresql/postgresql.conf",
    "-c", "hba_file=/etc/postgresql/pg_hba.conf",
  ]

  volumes = [
    "${asset.data.pg-config.postgresql_conf}:/etc/postgresql/postgresql.conf:ro",
    "${asset.data.pg-config.pg_hba_conf}:/etc/postgresql/pg_hba.conf:ro",
  ]
}

redis "data" "cache" {
  plugin { version = "0.14.0" }
  image  = "redis:8"
  # Default probes (tcp_socket liveness + redis-cli ping readiness)
  # ship for free.
}

app "myapp" "web" {
  image    = "ghcr.io/me/myapp:latest"
  replicas = 3
  ports    = ["8080"]

  env_from = ["myapp/shared"]              # DATABASE_URL / REDIS_URL / SLACK_WEBHOOK_URL come from here

  env = { PORT = "8080" NODE_ENV = "production" }

  init "migrate" {
    command = ["bin/rails", "db:migrate"]
    timeout = "10m"
  }

  probes {
    startup   { http_get { path = "/health" port = 8080 } period = "2s"  failure_threshold = 30 }
    liveness  { http_get { path = "/health" port = 8080 } period = "10s" failure_threshold = 3 }
    readiness { http_get { path = "/ready"  port = 8080 } period = "5s"  failure_threshold = 1 success_threshold = 2 }
  }

  autoscale {
    min        = 3
    max        = 15
    cpu_target = 60
    cooldown_down = "10m"
  }

  on_deploy {
    success { url = "${SLACK_WEBHOOK_URL}" }
    failure {
      url     = "${SLACK_WEBHOOK_URL}"
      headers = { "X-Voodu-Source" = "rollout" }
    }
  }

  host = "myapp.example.com"

  tls {
    email = "ops@example.com"
  }
}
```

```sh
# One-time setup: bucket holds EVERY ${VAR} the manifest references.
# env_from = ["myapp/shared"] feeds these into BOTH parse-time
# interpolation AND container runtime env.
PG_PASS=$(openssl rand -hex 16)
vd config set -s data -n pg POSTGRES_PASSWORD=$PG_PASS

vd config set -s myapp -n shared \
  DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp" \
  REDIS_URL="redis://cache-0.data:6379/0" \
  SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../XXXX"

vd apply -f voodu.hcl
```

## Private registry + app

```hcl
# voodu.hcl
registry "ghcr" {
  url      = "ghcr.io"
  username = "${GHCR_USER}"
  token    = "${GHCR_TOKEN}"
}

deployment "prod" "api" {
  image    = "ghcr.io/acme/private-api:1.4"
  replicas = 2
  ports    = ["3000"]
}
```

```sh
# IMPORTANT: registry secrets do NOT support env_from (one-credential-
# per-host constraint). Use a service-account / bot token distributed
# via gitignored .envrc + direnv (or password manager):
#
#   # .envrc (gitignored)
#   export GHCR_USER="acme-deploy-bot"
#   export GHCR_TOKEN="ghp_REPLACE_WITH_BOT_PAT"
#
# Per-dev personal PATs trample each other on the host.

vd apply -f voodu.hcl
```

## On-deploy webhook with rich body (PagerDuty Events v2)

For receivers that need a specific JSON schema (PagerDuty, Datadog, Slack Block Kit), use an asset-backed body template:

```hcl
# webhooks/pagerduty-event.json (committed in your repo):
# {
#   "routing_key": "${PD_ROUTING_KEY}",
#   "event_action": "trigger",
#   "payload": {
#     "summary": "voodu rollout failed: {{scope}}/{{name}}",
#     "source": "{{scope}}/{{name}}",
#     "severity": "error",
#     "custom_details": {
#       "release_id": "{{release_id}}",
#       "image": "{{image}}",
#       "error": "{{error}}"
#     }
#   }
# }

asset "prod" "webhooks" {
  pagerduty_event = file("./webhooks/pagerduty-event.json")
}

deployment "prod" "api" {
  image    = "ghcr.io/acme/api:1.4"
  env_from = ["prod/shared"]

  on_deploy {
    success { url = "${SLACK_WEBHOOK_URL}" }

    failure {
      url  = "https://events.pagerduty.com/v2/enqueue"
      file = "${asset.prod.webhooks.pagerduty_event}"
    }
  }
}
```

`${PD_ROUTING_KEY}` is substituted parse-time (from `prod/shared` bucket). `{{name}}`, `{{error}}`, etc. are substituted fire-time on the controller with the live release data.


## Raw docker pass-throughs (ulimits + docker_options)

```hcl
deployment "prod" "search" {
  image = "ghcr.io/me/search:1.0"

  ulimits = {
    nofile  = "1048576:1048576"
    memlock = "-1"
  }

  docker_options = [
    "--shm-size=2g",
    "--sysctl=net.core.somaxconn=4096",
  ]
}
```

Per-key override of platform-default ulimits (`nofile=65536:65536`, `nproc=4096:4096`); `docker_options` is a verbatim list-of-strings bypass appended to `docker run` before the image. Both available on every kind (deployment, statefulset, job, cronjob, app, per-init). Plugin blocks (postgres, redis, mongo, caddy) accept them at the HCL surface; whether the plugin forwards them is plugin-specific. Footgun: do not duplicate flags voodu already manages.
