# `vd logs` — stream container logs

```sh
vd logs clowk-lp/web                   # all replicas, follow mode
vd logs clowk-lp/web -f                # explicit follow
vd logs clowk-lp/web --tail 100        # last 100 lines
vd logs clowk-lp -f                    # entire scope (multiplexed, color-coded)
vd logs clowk-lp-web.abc123            # single container by name
```

stdout and stderr are merged in the stream.

## Common recipes

```sh
# Tail last hour of errors:
vd logs clowk-lp/web --since 1h | grep -i error

# Inspect a stuck cronjob run:
vd logs clowk-lp/nightly-backup -f

# Side-by-side scope view (every container in scope, prefixed):
vd logs clowk-lp -f

# Plugin logs (e.g. ingress):
vd logs voodu-caddy
```
