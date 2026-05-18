# Patterns

## 1. Multi-env: one manifest, N servers

Single file (`app.voodu`), only `-r` changes:

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

## 2. Shared scope (many repos, one scope)

Each repo declares only its own slice:

```hcl
# repo clowk/
deployment "clowk" "app" { image = "ghcr.io/clowk/app:1" }

# repo clowk-lp/
deployment "clowk" "lp"  { image = "ghcr.io/clowk/lp:1" }

# repo clowk-api/
deployment "clowk" "api" { image = "ghcr.io/clowk/api:1" }
```

CI for each repo, plain apply (no `--prune`):

```sh
vd apply -f voodu.hcl -r prod         # DO NOT pass --prune
```

Since the default is upsert-only, each repo applies only its slice without touching siblings. Passing `--prune` would wipe the other deployments in the same `(scope, kind)`.

> When to prefer a scope-per-repo instead: when you don't actually need to **group** the apps. Make them `clowk-app`, `clowk-lp`, `clowk-api` — ownership is obvious, and you can use `--prune` freely in each.

## 3. Build-mode vs image-mode

**Build-mode** (no CI needed — commitless):

```hcl
deployment "clowk" "api" {
  path     = "."
  replicas = 2
  ports    = ["8080"]

  lang { name = "ruby" version = "3.3" }
}
```

```sh
vd apply -f voodu.hcl -r prod   # tarball of CWD → SSH → server-side build
```

**Image-mode** (pull from registry):

```hcl
deployment "clowk" "api" {
  image    = "ghcr.io/clowk/api:1.2.3"
  replicas = 2
}
```

Build-mode is content-addressed: the same tree produces the same build-id, so the server skips rebuilds. Force one with `VOODU_FORCE_REBUILD=1 vd apply ...`.

## 4. Assets — configs as files

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

Edit `./configs/postgresql.conf` locally → `vd apply` → asset hash changes → automatic rolling restart. No `vd restart` needed.

## 5. Seeding secrets before the first apply

Stateful resources (postgres, redis) need passwords. Order:

```sh
PG_PASS=$(openssl rand -hex 16)

# 1. Create the config bucket BEFORE the statefulset exists
vd config data/pg set POSTGRES_PASSWORD=$PG_PASS

# 2. Wire the consumer
vd config myapp/web set \
  DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp"

# 3. Now apply
vd apply -f voodu.hcl
```

## 6. env_from — ConfigMap-style

```sh
vd config aws/cli set \
  AWS_ACCESS_KEY_ID=... \
  AWS_SECRET_ACCESS_KEY=... \
  AWS_REGION=us-east-1
```

```hcl
cronjob "clowk" "s3-backup" {
  schedule = "0 4 * * *"
  image    = "amazon/aws-cli"
  command  = ["s3", "sync", "/data", "s3://backups/clowk"]
  env_from = ["aws/cli"]              # inherits all keys
}
```

The virtual bucket `aws/cli` exists without a declared manifest.

## 7. Plugin macro with customisation

`postgres` is a thin alias of `statefulset` — operator declares overrides, plugin fills the rest:

```hcl
postgres "data" "pg" {
  plugin { version = "0.2.0" }

  # everything below wins over the plugin defaults:
  image    = "postgres:15-alpine"
  replicas = 2                        # primary + 1 replica

  command = [
    "postgres",
    "-c", "max_connections=200",
    "-c", "shared_buffers=2GB",
  ]
}
```

For full config, use `asset` + `command = ["postgres", "-c", "config_file=..."]`.

## 8. CI gating with `vd diff`

```sh
vd diff -f voodu.hcl --detailed-exitcode
# exit 0 = no changes
# exit 1 = error
# exit 2 = changes pending
```

Fail the PR on drift, or gate the apply step behind an explicit "yes there are changes" signal.

## 9. Persistent volumes — surviving delete

```hcl
statefulset "data" "pg" {
  volume_claim "data" { mount_path = "/var/lib/postgresql/data" }
}
```

```sh
vd delete statefulset/data/pg           # delete the pod, KEEP the volume
vd apply -f voodu.hcl                   # recreate the pod, data intact

vd delete statefulset/data/pg --prune   # delete pod AND volume (irreversible)
```
