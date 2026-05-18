---
description: vd config — env vars (set/get/list/reload, virtual buckets)
---

Display the following cheat sheet to the user, verbatim, as markdown.

# `vd config` — env vars

Env vars live **outside the manifest**. Values set via `vd config set` always win over `env {}` blocks in HCL.

## Verbs

```sh
vd config <ref> set KEY=val [KEY2=val2 ...]
vd config <ref> get [KEY]            # substring filter; no arg = list
vd config <ref> unset KEY
vd config <ref> list
vd config <ref> reload               # recreate the active container with new env
```

`:` shorthand also works: `vd config:set clowk-lp/web FOO=bar`.

## Refs

```sh
vd config clowk-lp/web set KEY=val   # single resource
vd config clowk-lp set KEY=val       # entire scope
vd config aws/cli set AWS_KEY=...    # virtual bucket (ConfigMap-style, no manifest)
```

Virtual buckets don't need a declared manifest. Consume them via `env_from = ["aws/cli"]`.

## Recipes

### Seed a postgres secret before the first apply

```sh
PG_PASS=$(openssl rand -hex 16)
vd config data/pg set POSTGRES_PASSWORD=$PG_PASS

vd config myapp/web set \
  DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp"
```

### Read values

```sh
vd config clowk-lp/web list
vd config clowk-lp/web get DATABASE_URL                 # substring match
vd config clowk-lp/web get -o json | jq '.DATABASE_URL' # exact extraction
```

### Shared bucket across resources

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
  env_from = ["aws/cli"]
}
```

### Rotate a secret without re-applying

```sh
vd config clowk-lp/web set SECRET_KEY=$(openssl rand -hex 32)
vd config clowk-lp/web reload
```
