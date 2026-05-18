# Exemplos prontos pra colar

## App simples (deployment + ingress + TLS)

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
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@example.com"
  }
}
```

```sh
vd apply -f voodu.hcl
```

## App build-mode (sem imagem prévia)

```hcl
deployment "clowk" "api" {
  path     = "."
  replicas = 2
  ports    = ["8080"]

  lang { name = "bun" version = "1.1" }

  health_check = "/healthz"
}

ingress "clowk" "api" {
  host = "api.example.com"

  tls {
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@example.com"
  }
}
```

```sh
vd apply -f voodu.hcl   # tarball do CWD → SSH → build no server
```

## Postgres single-node + app

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
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@example.com"
  }
}
```

```sh
PG_PASS=$(openssl rand -hex 16)
vd config set -s data -n pg POSTGRES_PASSWORD=$PG_PASS
vd config set -s myapp DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp"
vd apply -f voodu.hcl
```

## Cronjob de backup S3

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
# bucket compartilhado pra credenciais
vd config set aws/cli \
  AWS_ACCESS_KEY_ID=... \
  AWS_SECRET_ACCESS_KEY=... \
  AWS_REGION=us-east-1

vd apply -f cronjob.hcl

# rodar agora, sem esperar schedule:
vd run clowk/s3-backup
```

## Migração one-shot (`job`)

```hcl
job "clowk-lp" "migrate" {
  image    = "ghcr.io/clowk/lp:latest"
  command  = ["rails", "db:migrate"]

  env_from = ["clowk-lp/web"]    # herda DATABASE_URL etc do web
  timeout  = "10m"
}
```

```sh
vd apply -f voodu.hcl
vd run clowk-lp/migrate
vd logs clowk-lp/migrate -f
```

## Versioned API (mesmo host, paths diferentes)

```hcl
deployment "acme" "api-v1" { image = "ghcr.io/acme/api-v1:latest" }
deployment "acme" "api-v2" { image = "ghcr.io/acme/api-v2:latest" }

ingress "acme" "api-v1" {
  host    = "api.example.com"
  service = "api-v1"
  location { path = "/api/v1" }

  tls {
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@example.com"
  }
}

ingress "acme" "api-v2" {
  host    = "api.example.com"
  service = "api-v2"
  location { path = "/api/v2" }

  tls {
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@example.com"
  }
}
```

## Wildcard multi-tenant (`*.minhasaas.io`)

```hcl
ingress "saas" "tenants" {
  host    = "*.minhasaas.io"
  service = "app"
  port    = 3000

  tls {
    enabled   = true
    provider  = "letsencrypt"
    email     = "ssl@minhasaas.io"
    on_demand = true
    ask       = "http://app:3000/internal/allow_domain"
  }
}
```

Seu app precisa servir `GET /internal/allow_domain?domain=foo.minhasaas.io` → 200 (allow) ou 4xx (deny).

## Stack completo: postgres + redis + app + ingress

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
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@example.com"
  }
}
```

```sh
# Setup uma vez:
PG_PASS=$(openssl rand -hex 16)
vd config set -s data -n pg POSTGRES_PASSWORD=$PG_PASS
vd config set -s myapp \
  DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp" \
  REDIS_URL="redis://cache-0.data:6379/0"

vd apply -f voodu.hcl
```
