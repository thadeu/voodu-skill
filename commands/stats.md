---
description: vd stats — live CPU/memory usage joined with configured limits
---

Display the following cheat sheet to the user, verbatim, as markdown.

# `vd stats` — live resource usage

`vd stats` is `docker stats` for voodu-managed pods, joined with the manifest's configured `resources.limits` so you see usage **and** the ceiling in one table.

Single-shot (no streaming). For a refresh loop, pipe through `watch`.

## Usage

```sh
vd stats                             # every running pod
vd stats clowk-lp                    # one scope
vd stats clowk-lp/web                # one resource (all replicas)
vd stats deployment                  # all deployments (any scope)
vd stats deployment/clowk-lp/web     # explicit kind/scope/name
vd stats --orphans                   # include leaks / pre-M0 legacy pods
vd stats -o json                     # composable JSON
```

## Output columns

| col | meaning |
|---|---|
| KIND | `deployment` / `statefulset` / `job` / `cronjob`. `(orphan)` suffix means no matching manifest. |
| REF | `scope/name.replica` — the operator's mental model. |
| CPU% | Host-relative, matches docker stats. 100% = one full core. |
| MEM USED | Resident set size in human units (KiB/MiB/GiB). |
| MEM LIMIT | The manifest's `resources.limits.memory` verbatim ("254Mi"). `—` = unbounded. |
| MEM% | `MEM USED / docker_cgroup_limit * 100` — docker's own number. |
| CPU LIMIT | The manifest's `resources.limits.cpu` verbatim ("0.4", "500m"). `—` = unbounded. |

## Filters

Three sources, all equivalent on the wire:

```sh
# Positional ref (preferred — matches `vd logs` / `vd get` style):
vd stats deployment/clowk-lp/web

# Explicit flags (for scripts where the ref is split across vars):
vd stats -k deployment -s clowk-lp -n web

# Mix is rejected — pick one.
vd stats clowk-lp -k deployment   # ERROR: not both
```

Single-segment refs disambiguate: `deployment`/`statefulset`/`job`/`cronjob`/`ingress` → `--kind`; anything else → `--scope`.

## Recipes

```sh
# Spot pods approaching their memory limit:
vd stats -o json | jq '.[] | select(.usage.memory_percent > 80)'

# Snapshot CPU across all replicas of one app:
vd stats clowk-lp/web -o json | jq '[.[] | .usage.cpu_percent] | add / length'

# Find leaks (containers running but no manifest):
vd stats --orphans -o json | jq '.[] | select(.orphan)'

# Refresh loop (poor man's streaming):
watch -n 2 vd stats clowk-lp
```

## Notes

- Stopped pods are omitted by design (no cgroup to sample). `vd get pods` shows them.
- Orphans (no voodu labels, or labels but no manifest) are hidden by default — opt in with `--orphans`.
- The Go-side types (`controller.PodStats`, `StatsFilter`, etc.) are reusable from a future SDK; the join is in `internal/controller/stats.go` if you need to plug another consumer.
