# `vd exec` — shell into a running container

```sh
vd exec clowk-lp/web -- bash           # auto-pick best replica
vd exec clowk-lp/web -- ls -la /app
vd exec clowk-lp-web.abc123 -- sh      # specific container
vd exec data/pg.0 -- psql -U postgres  # statefulset by ordinal
```

TTY and stdin are auto-detected. Same surface as `docker exec` for `--workdir`, `--user`, etc.

## Compared to `vd run`

| Verb | Behaviour |
|---|---|
| `vd exec` | Enter a **live** container. |
| `vd run <ref> -- cmd` | Spawn a **fresh** container from the resource spec. |
| `vd apply` | Desired state, not one-shot. |

## Recipes

```sh
# Rails console:
vd exec clowk-lp/web -- bin/rails console

# Inspect mounted assets:
vd exec data/pg.0 -- ls /etc/postgresql

# Debug a misbehaving container:
vd exec clowk-lp-web.abc123 -- bash
```
