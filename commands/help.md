---
description: voodu cheat sheet — every slash command at a glance
---

Display the following cheat sheet to the user, verbatim, as markdown.

# voodu / vd — slash command index

`vd` is an alias of `voodu`. Type any of these for a focused cheat sheet.

| Command | What it covers |
|---|---|
| `/vd:apply` | Apply a manifest, prune semantics, flags |
| `/vd:diff` | Preview changes, CI exit codes |
| `/vd:delete` | Delete resources (file, scope, name, pod) |
| `/vd:config` | Env vars (set/get/list/reload, virtual buckets) |
| `/vd:logs` | Tail container logs (single, scope, multiplexed) |
| `/vd:exec` | Shell into a running container |
| `/vd:run` | One-shot jobs / cronjobs / deployment commands |
| `/vd:restart` | Rolling restart without changing the manifest |
| `/vd:rollback` | Revert a deployment to a past release |
| `/vd:release` | Re-trigger the release phase |
| `/vd:describe` | Full state for a resource (manifest + status + pods) |
| `/vd:get` | List pods or other resources |
| `/vd:stats` | Live CPU/memory usage joined with configured limits |
| `/vd:remote` | SSH remotes for multi-server deploys |
| `/vd:plugins` | Install / list / update plugins |
| `/vd:manifests` | Every HCL kind (deployment, ingress, statefulset, ...) |
| `/vd:patterns` | Multi-env, shared-scope, build-mode, assets |
| `/vd:examples` | Ready-to-paste manifests |

## Voodu fundamentals (top of mind)

- **Default: upsert-only.** `vd apply` only creates/updates. Pass `--prune` to delete what disappeared.
- **Secrets stay out of HCL.** Use `vd config set` — overrides `env {}` blocks.
- **`scope` is a free-form grouping label.** Names are unique per scope.
- **Build-mode vs image-mode.** `image = "..."` and `build { ... }` are mutually exclusive. With `image`, the server pulls from the registry. With `build { context = "..." }` (or just omit both for auto-detect at repo root), the CLI tarballs the working tree and ships it over SSH.
- **TLS defaults.** Declaring `tls {}` on an ingress (even bare) flips `enabled = true` and `provider = "letsencrypt"`. Omit the block entirely to disable TLS.
