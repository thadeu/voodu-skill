# `vd config` — env vars

Application env vars live **outside the manifest** — secrets stay out of git. Values set via `vd config set` always win over `env {}` blocks in HCL.

## Verbs

```sh
vd config <ref> set KEY=val [KEY2=val2 ...]
vd config <ref> get [KEY]
vd config <ref> unset KEY
vd config <ref> list
vd config <ref> reload         # recreate the active container with the new env
```

The `:` shorthand also works:

```sh
vd config:set clowk-lp/web FOO=bar    # same as `vd config clowk-lp/web set FOO=bar`
```

## Accepted refs

```sh
vd config clowk-lp/web set KEY=val     # single resource
vd config clowk-lp set KEY=val         # entire scope (every resource)
vd config aws/cli set AWS_KEY=...      # virtual bucket (ConfigMap-style)
```

Virtual buckets don't need a manifest — just `set` them, then `env_from` from any consumer.

## Examples

### Seed a postgres secret before the first apply

```sh
PG_PASS=$(openssl rand -hex 16)
vd config data/pg set POSTGRES_PASSWORD=$PG_PASS

# And the consumer:
vd config myapp/web set \
  DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp" \
  REDIS_URL="redis://cache-0.data:6379/0"
```

### Read values

```sh
vd config clowk-lp/web list                              # all keys + values
vd config clowk-lp/web get DATABASE_URL                  # one key
vd config clowk-lp/web get -o json | jq '.DATABASE_URL'  # exact match
```

`get` filters by **substring**, not exact match. Use `-o json | jq` when you need exact extraction.

### Share config across resources (ConfigMap-style)

```sh
# shared bucket
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

  env_from = ["aws/cli"]      # inherits every AWS_* key
}
```

### Reload — apply new env without re-applying the manifest

```sh
vd config clowk-lp/web set FEATURE_FLAG=on
vd config clowk-lp/web reload
```

Useful for rotating a secret without running `vd apply`.
