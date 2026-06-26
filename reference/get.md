# `vd get` — read-only listings

## Pods

```sh
vd get pods                        # everything
vd get pods -s clowk-lp            # filter by scope
vd get pods clowk-lp/web           # one resource (all replicas)
vd get pods -o json                # JSON for piping into jq
```

## Single pod

```sh
vd get pod clowk-lp-web.abc123     # alias of `vd describe pod`
```

## Recipes

```sh
# List all containers in a scope:
vd get pods -s clowk-lp

# Find pods by status:
vd get pods -o json | jq '.[] | select(.status != "running")'

# Count replicas of every deployment:
vd get pods -o json | jq 'group_by(.resource) | map({key: .[0].resource, count: length})'
```

## For other kinds

`vd describe` is the right verb for one-resource detail. For listings beyond pods, use `-o json` and pipe into jq, or check the controller directly:

```sh
vd describe deployment clowk-lp/web
vd describe statefulset data/pg
```
