# Manifestos HCL — todos os kinds

Todos os kinds escopados usam **duas labels**: `<scope>` e `<name>`.
Scope agrupa, name é único dentro do scope.

## `deployment` — stateless

```hcl
deployment "clowk" "api" {
  image    = "ghcr.io/clowk/api:1.2.3"   # ou path para build-mode
  replicas = 2
  ports    = ["8080"]

  env = {
    PORT = "8080"
    NODE_ENV = "production"
  }

  restart      = "always"                # always|on-failure|no
  health_check = "/healthz"              # default "/"
}
```

**Build-mode** (sem `image`):

```hcl
deployment "clowk" "api" {
  path     = "."                         # CWD do `vd apply`
  replicas = 2
  ports    = ["8080"]

  lang { name = "bun" }                  # go|ruby|python|node|bun…
}
```

Campos disponíveis: `image`, `path`, `workdir`, `dockerfile`, `replicas`, `command`, `env`, `env_file`, `ports`, `volumes`, `network`, `networks`, `network_mode`, `restart`, `health_check`, `post_deploy`, `keep_releases`, `extra_hosts`, `cap_add`, `build_args`, blocos: `lang`, `release`, `depends_on`, `resources`.

### Ports — loopback-only por default

`ports = ["8080"]` mapeia em `127.0.0.1:8080`. Pra expor publicamente, declare IP explicitamente:

```hcl
ports = ["0.0.0.0:8080:8080"]
```

Mas em geral exposição pública vai por **ingress**, não pelo deployment.

### Resources (CPU/memory, k8s-style)

```hcl
deployment "clowk" "api" {
  image = "..."

  resources {
    limits {
      cpu    = "2"          # ou "500m"
      memory = "1Gi"        # ou "512Mi", "2G", bytes
    }
  }
}
```

### Release phase (pré/pós deploy)

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

## `statefulset` — stateful, pods com identidade

```hcl
statefulset "data" "pg" {
  image    = "postgres:15-alpine"
  replicas = 1
  ports    = ["5432"]

  env = {
    POSTGRES_DB = "myapp"
    PGDATA      = "/var/lib/postgresql/data/pgdata"
    # senha NUNCA aqui — use `vd config set`
  }

  volume_claim "data" {
    mount_path = "/var/lib/postgresql/data"
  }
}
```

Diferenças do `deployment`:
- Pods têm DNS estável: `pg-0.data`, `pg-1.data` (+ round-robin `pg.data`).
- Cada ordinal tem volume Docker próprio (`voodu-data-pg-data-0`, …).
- Volumes sobrevivem a restart/rebuild. Só somem com `vd delete … --prune`.

## `ingress` — host routing + TLS

```hcl
ingress "clowk" "api" {
  host = "api.clowk.in"
  port = 8080              # opcional se deployment já declara

  tls {
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@clowk.in"
  }
}
```

**Service** default = nome do ingress. Rotear cross-app:

```hcl
ingress "public" "api_http" {
  host    = "api.internal"
  service = "api"          # aponta pra deployment "public" "api"
  port    = 3000
}
```

### 4 perfis TLS (precisa do plugin voodu-caddy)

```hcl
# HTTP only — sem TLS block
ingress "x" "http" { host = "api.local"; service = "api" }

# Let's Encrypt
tls { enabled = true; provider = "letsencrypt"; email = "ops@x.com" }

# Self-signed (dev)
tls { enabled = true; provider = "internal" }

# On-demand wildcard (single legit profile pra *.dominio)
tls {
  enabled   = true
  provider  = "letsencrypt"
  email     = "ssl@x.com"
  on_demand = true
  ask       = "http://app:3000/internal/allow_domain"   # OBRIGATÓRIO
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

Strip prefix antes do upstream:

```hcl
location {
  path  = "/docs/voodu"
  strip = true             # backend vê /getting-started
}
```

## `app` — sugar pra deployment + ingress

```hcl
app "myapp" "web" {
  image    = "ghcr.io/myorg/myapp:latest"
  replicas = 3
  ports    = ["8080"]

  env = { PORT = "8080" }

  health_check = "/healthz"

  # Ingress side
  host = "myapp.example.com"

  tls {
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@example.com"
  }
}
```

Internamente expande pra `deployment + ingress` com o mesmo `(scope, name)`.

## `job` — execução one-shot manual

```hcl
job "clowk-lp" "migrate" {
  image = "ghcr.io/clowk/lp:latest"

  command = ["rails", "db:migrate"]

  env = { RAILS_ENV = "production" }
  env_from = ["clowk-lp/web"]    # herda config da deployment "web"

  timeout = "10m"
}
```

Roda só quando você chama: `vd run clowk-lp/migrate`.

## `cronjob` — job agendado

```hcl
cronjob "clowk-lp" "nightly-backup" {
  schedule = "0 3 * * *"
  timezone = "America/Sao_Paulo"

  image   = "ghcr.io/clowk/lp:latest"
  command = ["rake", "backup:run"]

  env_from = ["clowk-lp/web"]

  concurrency_policy        = "Forbid"   # Allow|Forbid|Replace
  successful_history_limit  = 3
  failed_history_limit      = 5
}
```

## `asset` — file bundles declarativos

Materializa arquivos no host pra serem montados:

```hcl
asset "data" "redis-config" {
  configuration = file("./configs/redis.conf")   # local, lido no apply
  acl_users     = url("https://r2.example.com/acl")  # remoto, fetched pelo server
  motd          = "Welcome to redis"             # literal
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

**Scoped** (`asset "scope" "name"`): ref de 4 segmentos `${asset.scope.name.key}`.
**Unscoped** (`asset "name"`): ref de 3 segmentos `${asset.name.key}` — pra CA bundles compartilhados, etc.

Edita o arquivo local → re-apply → hash do asset muda → rolling restart automático.

## Macros (postgres, redis, mongo) — plugins

```hcl
postgres "data" "pg" {
  plugin { version = "0.2.0" }      # ou "latest"
  image  = "postgres:15-alpine"
}

redis "data" "cache" {
  plugin { version = "latest" }
  image  = "redis:8"
}
```

Expande server-side em `statefulset`. Defaults vêm do plugin; tudo declarado vence.

## Variáveis interpoladas

- `${VAR}` ou `${VAR:-default}` — env do shell (resolvido na CLI).
- `${asset.scope.name.key}` — bind mount do asset.
- `file("./path")` — lê do CWD da CLI.
- `url("https://...")` — fetched pelo controller, cached por ETag.
