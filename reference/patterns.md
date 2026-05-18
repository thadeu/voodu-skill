# Patterns úteis

## 1. Multi-env: 1 manifesto, N servidores

Arquivo único (`app.voodu`), só muda `-r`:

```hcl
deployment "clowk-lp" "web" {
  image    = "ghcr.io/clowk/lp:${IMAGE_TAG:-latest}"
  replicas = 2
  ports    = ["8080"]
  env = { PORT = "8080" }
}

ingress "clowk-lp" "web" {
  host = "${APP_HOST:-clowk.in}"

  tls {
    enabled  = true
    provider = "letsencrypt"
    email    = "ops@clowk.in"
  }
}
```

```sh
APP_HOST=staging.clowk.in IMAGE_TAG=v1.2.3 vd apply -f app.voodu -r staging
APP_HOST=clowk.in        IMAGE_TAG=v1.2.3 vd apply -f app.voodu -r prod-1
```

## 2. Shared scope (vários repos, mesmo scope)

Cada repo declara só seu pedaço:

```hcl
# repo clowk/
deployment "clowk" "app" { image = "ghcr.io/clowk/app:1" }

# repo clowk-lp/
deployment "clowk" "lp"  { image = "ghcr.io/clowk/lp:1" }

# repo clowk-api/
deployment "clowk" "api" { image = "ghcr.io/clowk/api:1" }
```

CI pipeline em todos, sem `--prune`:

```sh
vd apply -f voodu.hcl -r prod         # NÃO passa --prune
```

Como o default é upsert-only, cada repo aplica só o seu sem mexer nos outros. Se algum CI passar `--prune`, apaga os irmãos no mesmo `(scope, kind)`.

> Quando preferir scope por repo: se você não precisa **agrupar** os apps. Aí vira `clowk-app`, `clowk-lp`, `clowk-api` — ownership óbvio, e dá pra usar `--prune` à vontade em cada um.

## 3. Build-mode vs image-mode

**Build-mode** (CI nem precisa, é commitless):

```hcl
deployment "clowk" "api" {
  path     = "."
  replicas = 2
  ports    = ["8080"]

  lang { name = "ruby" version = "3.3" }
}
```

```sh
vd apply -f voodu.hcl -r prod   # tarball do CWD → SSH → build no server
```

**Image-mode** (pulla do registry):

```hcl
deployment "clowk" "api" {
  image    = "ghcr.io/clowk/api:1.2.3"
  replicas = 2
}
```

Build-mode é content-addressed: mesma árvore = mesmo build-id, server pula rebuild. Pra forçar: `VOODU_FORCE_REBUILD=1 vd apply ...`.

## 4. Assets — configs como arquivo

`postgresql.conf`, `redis.conf`, ACLs, MOTDs:

```hcl
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
```

Edita `./configs/postgresql.conf` localmente → `vd apply` → hash do asset muda → rolling restart automático. Sem `vd restart`.

## 5. Secret seeding antes do primeiro apply

Stateful (postgres, redis) precisa de senha. Ordem:

```sh
PG_PASS=$(openssl rand -hex 16)

# 1. Cria bucket de config ANTES do statefulset existir
vd config set -s data -n pg POSTGRES_PASSWORD=$PG_PASS

# 2. Cria buckets do app (DATABASE_URL etc)
vd config set -s myapp DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp"

# 3. Agora sim, apply
vd apply -f voodu.hcl
```

## 6. env_from — ConfigMap-style

```sh
vd config set aws/cli AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1
```

```hcl
cronjob "clowk" "s3-backup" {
  schedule = "0 4 * * *"
  image    = "amazon/aws-cli"
  command  = ["s3", "sync", "/data", "s3://backups/clowk"]
  env_from = ["aws/cli"]              # herda tudo
}
```

Bucket virtual `aws/cli` existe sem manifesto declarado.

## 7. Plugin macro com customização

`postgres` é dumb alias de `statefulset` — operator declara overrides, plugin preenche o resto:

```hcl
postgres "data" "pg" {
  plugin { version = "0.2.0" }

  # tudo abaixo vence o default do plugin:
  image    = "postgres:15-alpine"
  replicas = 2                        # primary + 1 replica

  command = [
    "postgres",
    "-c", "max_connections=200",
    "-c", "shared_buffers=2GB",
  ]
}
```

Pra config completa, use `asset` + `command = ["postgres", "-c", "config_file=..."]`.

## 8. CI gating com `vd diff`

```sh
vd diff -f voodu.hcl --detailed-exitcode
# exit 0 = no changes
# exit 1 = error
# exit 2 = changes pending
```

Falha o PR se houver drift, ou exige apply manual depois do merge.

## 9. Volumes persistentes — sobreviver a delete

```hcl
statefulset "data" "pg" {
  volume_claim "data" { mount_path = "/var/lib/postgresql/data" }
}
```

```sh
vd delete statefulset/data/pg           # apaga pod, MANTÉM volume
vd apply -f voodu.hcl                   # recria pod, dados intactos

vd delete statefulset/data/pg --prune   # apaga pod E volume (irreversível)
```
