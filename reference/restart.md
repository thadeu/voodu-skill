# `vd restart` / `vd stop` / `vd start`

## Rolling restart

```sh
vd restart clowk-lp/web                # deployment or statefulset
```

Doesn't change the manifest, just recreates containers in a rolling fashion. Useful for:

- Picking up a fresh `:latest` image
- Reloading env vars after `vd config set` (or use `vd config reload`)
- Clearing a hung worker

## Stop / start

```sh
vd stop clowk-lp/web                   # stop every replica
vd stop clowk-lp/web.0                 # stop just ordinal 0 (statefulset)
vd start clowk-lp/web                  # clear freeze + recreate
```

`stop` marks the resource as **frozen** — re-applying the manifest will NOT recreate it. `start` releases the freeze.

## Recipes

```sh
# Rolling restart after rotating a secret:
vd config clowk-lp/web set SECRET=$(openssl rand -hex 32)
vd restart clowk-lp/web

# Temporarily disable a deployment:
vd stop clowk-lp/web
# ... do maintenance ...
vd start clowk-lp/web

# Stop a single misbehaving postgres replica without killing the primary:
vd stop statefulset/data/pg.1
```
