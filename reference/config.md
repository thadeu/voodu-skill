# `vd config` — env vars

Env vars de aplicação são gerenciadas **fora do manifesto** — secrets ficam longe do repo. Valor de `vd config set` **sempre vence** sobre `env {}` do HCL.

## Verbos

```sh
vd config <ref> set KEY=val [KEY2=val2 …]
vd config <ref> get [KEY]
vd config <ref> unset KEY
vd config <ref> list
vd config <ref> reload         # recria container ativo com env novo
```

Também aceita sintaxe `:`:

```sh
vd config:set clowk-lp/web FOO=bar    # ≡ vd config clowk-lp/web set FOO=bar
```

## Refs aceitos

```sh
vd config clowk-lp/web set KEY=val      # 1 recurso
vd config clowk-lp set KEY=val          # scope inteiro (todos os recursos)
vd config aws/cli set AWS_KEY=...       # bucket virtual (ConfigMap-style)
```

Buckets virtuais existem sem manifesto declarado — basta criar via `set`, depois herdar com `env_from`.

## Exemplos

### Secret de postgres antes do primeiro apply

```sh
PG_PASS=$(openssl rand -hex 16)
vd config -s data -n pg set POSTGRES_PASSWORD=$PG_PASS

# E o consumer:
vd config -s myapp set \
  DATABASE_URL="postgres://postgres:$PG_PASS@pg-0.data:5432/myapp" \
  REDIS_URL="redis://cache-0.data:6379/0"
```

### Ler valores

```sh
vd config clowk-lp/web list             # tudo (chaves + valores)
vd config clowk-lp/web get DATABASE_URL # 1 chave
vd config clowk-lp/web get -o json | jq '.DATABASE_URL'    # programático
```

`get` filtra por **substring**, não exact-match. Use `-o json | jq` se precisar de chave exata.

### Compartilhar config entre recursos (ConfigMap-style)

```sh
# bucket compartilhado
vd config aws/cli set AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1

# qualquer cronjob/deployment herda:
```

```hcl
cronjob "clowk" "s3-backup" {
  schedule = "0 4 * * *"
  image    = "amazon/aws-cli"
  command  = ["s3", "sync", "/data", "s3://backups/clowk"]

  env_from = ["aws/cli"]      # herda AWS_* do bucket
}
```

### Reload — aplicar env sem mudar manifesto

```sh
vd config clowk-lp/web set FEATURE_FLAG=on
vd config clowk-lp/web reload
```

Útil pra rotacionar secret sem `vd apply`.
