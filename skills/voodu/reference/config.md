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

### `env_from` feeds parse-time `${VAR}` interpolation

`env_from` does TWO things — operator typically only thinks of (1) but (2) is often what makes a manifest work for an entire team:

1. **Runtime env file:** the controller stacks the bucket's KV pairs under the resource's own env via `--env-file`. The container reads them at boot.
2. **Parse-time `${VAR}` substitution:** the CLI fetches the bucket from the controller BEFORE parsing the manifest and layers its values into the `${VAR}` interpolation context. So `${SLACK_WEBHOOK_URL}` in `on_deploy.success.url` resolves from the bucket — no per-dev `export` needed.

```sh
# Set once on the controller:
vd config set -s prod -n shared \
  SLACK_WEBHOOK_URL="https://hooks.slack.com/..." \
  PD_ROUTING_KEY="R000..." \
  DATABASE_URL="postgres://..."
```

```hcl
deployment "prod" "api" {
  env_from = ["prod/shared"]                # bucket fed into ${VAR} at parse-time

  image = "ghcr.io/acme/api:1.4"

  env = {
    DATABASE_URL = "${DATABASE_URL}"        # resolves from prod/shared
  }

  on_deploy {
    success { url = "${SLACK_WEBHOOK_URL}" }   # ditto

    failure {
      url     = "https://events.pagerduty.com/v2/enqueue"
      headers = { "X-Routing-Key" = "${PD_ROUTING_KEY}" }
    }
  }
}
```

Every dev on the team applies without exporting anything locally. Rotation = one `vd config set` — propagates to every dev's next `vd apply`.

**Precedence (later wins, mirrors runtime env_from layering):**

1. env_from'd bucket vars, in declared order (later refs override earlier on the same key).
2. Operator's shell env wins over the bucket on collision — allows ad-hoc override for testing: `SLACK_WEBHOOK_URL=https://test/h vd apply ...`.

**Caveat:** the parse-time bucket lookup runs for **local applies only**. With `-r <remote>` the SSH-forward path keeps shell-only interpolation — use direnv / shell exports for remote applies.

**Exception:** the `registry` kind does NOT accept `env_from`. The one-credential-per-host constraint (`~/.docker/config.json` is singular) means a bucket wouldn't solve the underlying problem; use a service-account token via `.envrc` instead. See [reference/manifests.md](manifests.md#registry).

### Reload — apply new env without re-applying the manifest

```sh
vd config clowk-lp/web set FEATURE_FLAG=on
vd config clowk-lp/web reload
```

Useful for rotating a secret without running `vd apply`.
