---
description: voodu patterns — multi-env, shared-scope, build-mode, assets, secrets
---

Display the following cheat sheet to the user, verbatim, as markdown.

# voodu patterns

## 1. Multi-env: one manifest, N servers

Single file, only `-r` changes:

```hcl
deployment "clowk-lp" "web" {
  image = "ghcr.io/clowk/lp:${IMAGE_TAG:-latest}"
  replicas = 2
  ports = ["8080"]
}

ingress "clowk-lp" "web" {
  host = "${APP_HOST:-clowk.in}"
  tls { email = "ops@clowk.in" }
}
```

```sh
APP_HOST=staging.clowk.in IMAGE_TAG=v1.2.3 vd apply -f app.voodu -r staging
APP_HOST=clowk.in        IMAGE_TAG=v1.2.3 vd apply -f app.voodu -r prod-1
```

## 2. Shared scope (many repos, one scope)

```hcl
# repo clowk/        : deployment "clowk" "app" { ... }
# repo clowk-lp/     : deployment "clowk" "lp"  { ... }
# repo clowk-api/    : deployment "clowk" "api" { ... }
```

Each repo CI: `vd apply -f voodu.hcl -r prod` (NO `--prune`).

Default is upsert-only, so each repo applies only its slice. Adding `--prune` would wipe the siblings.

## 3. Build-mode vs image-mode

`image` and `build {}` are mutually exclusive — parse error if both. Omitting both gives auto-detect at repo root.

```hcl
# Build-mode (commitless deploy):
deployment "clowk" "api" {
  build {
    context = "."
    lang { name = "ruby" version = "3.3" }
  }
}

# Build-mode (custom Dockerfile + build args):
deployment "clowk" "api" {
  build {
    context    = "."
    dockerfile = "Dockerfile"
    args = { RUBY_VERSION = "3.3" }
  }
}

# Build-mode (auto-detect):
deployment "clowk" "api" {}      # no image, no build → builds repo root, sniffs runtime

# Image-mode (registry pull):
deployment "clowk" "api" {
  image = "ghcr.io/clowk/api:1.2.3"
}
```

## 4. Assets — configs as files

```hcl
asset "data" "pg-config" {
  postgresql_conf = file("./configs/postgresql.conf")
}

postgres "data" "pg" {
  command = ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]

  volumes = [
    "${asset.data.pg-config.postgresql_conf}:/etc/postgresql/postgresql.conf:ro",
  ]
}
```

Edit the local file → re-apply → asset hash changes → automatic rolling restart.

## 5. Seeding secrets before first apply

```sh
PG_PASS=$(openssl rand -hex 16)

# Before the statefulset exists:
vd config data/pg set POSTGRES_PASSWORD=$PG_PASS

# Wire consumer:
vd config myapp/web set DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp"

vd apply -f voodu.hcl
```

## 6. env_from — ConfigMap-style sharing

```sh
vd config aws/cli set AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
```

```hcl
cronjob "clowk" "s3-backup" {
  schedule = "0 4 * * *"
  image    = "amazon/aws-cli"
  command  = ["s3", "sync", "/data", "s3://backups/clowk"]
  env_from = ["aws/cli"]
}
```

## 7. CI gating with `vd diff`

```sh
vd diff -f voodu.hcl --detailed-exitcode
# 0 = no changes; 1 = error; 2 = changes pending
```

## 8. Persistent volumes — surviving delete

```sh
vd delete statefulset/data/pg           # keep volumes (data intact)
vd apply -f voodu.hcl                   # recreate pod, attach same volume

vd delete statefulset/data/pg --prune   # delete volumes too (irreversible)
```
