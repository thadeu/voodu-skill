# pods / logs / exec / run / restart / rollback

## `vd get pods` — list containers

```sh
vd get pods                        # everything
vd get pods -s clowk-lp            # scope
vd get pods clowk-lp/web           # single resource (all replicas)
vd get pods -o json                # programmatic
```

## `vd describe <kind> <ref>` — full detail

```sh
vd describe deployment clowk-lp/web    # manifest + status + pods
vd describe statefulset data/pg
vd describe ingress clowk-lp/web
```

`vd get pod <ref>` is an alias for `vd describe pod`.

## `vd logs` — stream container logs

```sh
vd logs clowk-lp/web                   # all replicas, follow mode
vd logs clowk-lp/web -f                # explicit follow
vd logs clowk-lp/web --tail 100        # last 100 lines
vd logs clowk-lp -f                    # entire scope (multiplexed)
vd logs clowk-lp-web.abc123            # single container
```

stdout and stderr are merged.

## `vd exec` — shell into a container

```sh
vd exec clowk-lp/web -- bash           # auto-pick best replica
vd exec clowk-lp/web -- ls -la /app
vd exec clowk-lp-web.abc123 -- sh      # specific container
```

TTY/stdin auto-detect by default. Same flag surface as `docker exec` for workdir/user.

## `vd run` — one-shot verb

Unified verb. Three behaviours, picked by ref shape:

```sh
# 1. Declared job → trigger once
vd run clowk-lp/migrate

# 2. Declared cronjob → force-tick (bypass schedule)
vd run clowk-lp/nightly-backup

# 3. Deployment + command → one-shot exec into a fresh container
vd run clowk-lp/web -- rails db:migrate
vd run clowk-lp/web -- rake clean
```

Without a command, `vd run` only works on a `job` or `cronjob` (the kinds that have a "trigger me once" meaning).

Quick distinctions:
- `vd exec` — enter an already-running container.
- `vd run <ref> -- cmd` — spawn a fresh container from the resource spec.
- `vd apply` — desired state.

## `vd restart` — rolling restart

```sh
vd restart clowk-lp/web                # deployment or statefulset
```

Doesn't change the manifest, just recreates containers. Useful for picking up a new `:latest`, reloading env, etc.

## `vd stop` / `vd start`

```sh
vd stop clowk-lp/web                   # all replicas
vd stop clowk-lp/web.0                 # just ordinal 0 (statefulset)
vd start clowk-lp/web                  # clear freeze + recreate
```

`stop` freezes the resource — a re-apply won't recreate it. `start` releases the freeze.

## `vd rollback` — revert to a past release

```sh
vd rollback clowk-lp/web               # previous release
vd rollback clowk-lp/web release-42    # specific release
```

Re-applies a past release's spec snapshot. History is retained up to `keep_releases` (default ~10).

## `vd release` — re-trigger the release phase

```sh
vd release clowk-lp/web                # re-run release_command
vd release clowk-lp/web list           # list releases
```

Useful when `release { command = ... }` failed and you want to re-run it without a fresh deploy.
