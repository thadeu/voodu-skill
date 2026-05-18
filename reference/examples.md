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
  plugin { version = "0.2.0" }
  image = "postgres:15-alpine"

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
  plugin { version = "latest" }
  image  = "redis:8"
}

app "myapp" "web" {
  image    = "ghcr.io/me/myapp:latest"
  replicas = 3
  ports    = ["8080"]

  env = { PORT = "8080" NODE_ENV = "production" }

  health_check = "/healthz"
  host         = "myapp.example.com"

  tls {
    email = "ops@example.com"
  }
}
```

```sh
# One-time setup:
PG_PASS=$(openssl rand -hex 16)
vd config data/pg set POSTGRES_PASSWORD=$PG_PASS
vd config myapp/web set \
  DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp" \
  REDIS_URL="redis://cache-0.data:6379/0"

vd apply -f voodu.hcl
```
