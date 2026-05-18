# Plugins

Plugins são binários independentes em `/opt/voodu/plugins`. Adicionam macros (`postgres`, `redis`, …) ou serviços (ingress).

## Plugins oficiais

| Repo | Pra que | Macro |
|---|---|---|
| `thadeu/voodu-caddy` | Ingress + TLS (Let's Encrypt, wildcard) | reconcilia `ingress` |
| `thadeu/voodu-postgres` | Postgres com backup/replica/promote | `postgres` |
| `thadeu/voodu-redis` | Redis com Sentinel HA | `redis` |
| `thadeu/voodu-mongo` | MongoDB | `mongo` |

## Comandos

```sh
vd plugins:install thadeu/voodu-caddy        # do GitHub
vd plugins:install thadeu/voodu-postgres
vd plugins:list
vd plugins:update                            # todos
vd plugins:update voodu-postgres             # 1 só
vd plugins:remove voodu-mongo
```

## Versão pelo HCL

Cada macro aceita `plugin { ... }`:

```hcl
postgres "data" "pg" {
  plugin {
    version = "0.2.0"               # tag específica, reinstall se mismatch
    # version = "latest"            # sempre re-fetch default branch
    # repo = "myorg/voodu-postgres-fork"   # fork override
  }
  image = "postgres:15-alpine"
}
```

Bloco omitido = usa o que está instalado, sem network roundtrip.

## Aliases de comando

Plugins podem declarar aliases:

```sh
vd pg:psql                # ≡ vd postgres:psql
vd pg:create main
vd pg:promote --replica 1 # promove pg-1 a primary
```

## Postgres — comandos comuns (plugin)

```sh
vd pg:create main                    # cria nova database
vd pg:list
vd pg:psql main                      # shell psql interativo
vd pg:backup main                    # snapshot
vd pg:restore main backup-2026-01-01
vd pg:promote --replica 1            # promover pg-1 a primary
vd pg:failover                       # alias de promote
```

## Redis — comandos (plugin)

```sh
vd redis:cli                         # redis-cli interativo
vd redis:failover                    # Sentinel-driven failover
```

## Caddy / ingress — não tem CLI extra

`voodu-caddy` é reativo: você declara `ingress { ... }` no HCL, controller reconcilia, Caddy gera config.

Pra ver o que Caddy aplicou:

```sh
vd describe ingress clowk/api
vd logs voodu-caddy                  # logs do reverse proxy
```
