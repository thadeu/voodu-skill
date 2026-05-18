---
name: voodu
description: Cheat sheet for the voodu / vd CLI (self-hosted PaaS, HCL manifests). Use whenever the user asks how to do something with voodu — running commands (apply, diff, delete, config, logs, exec, run, restart, rollback, remote, plugins), authoring HCL/YAML manifests (deployment, statefulset, ingress, app, asset, job, cronjob, postgres, redis, mongo), seeding secrets, or wiring multi-server / shared-scope / build-mode setups.
---

# voodu — cheat sheet

`vd` is an alias for the `voodu` binary (same command, shorter spelling).
This skill is a quick-reference — no theory, just recipes.

## Command map

| I want to… | Command |
|---|---|
| Apply a manifest | `vd apply -f voodu.hcl` |
| Preview changes | `vd diff -f voodu.hcl` |
| Delete resources | `vd delete <scope>/<name>` |
| List pods | `vd get pods` |
| Describe a resource | `vd describe deployment clowk-lp/web` |
| Tail logs | `vd logs clowk-lp/web -f` |
| Shell into a container | `vd exec clowk-lp/web -- bash` |
| Rolling restart | `vd restart clowk-lp/web` |
| Stop / start | `vd stop clowk-lp/web` / `vd start clowk-lp/web` |
| Trigger a declared job | `vd run clowk-lp/migrate` |
| One-shot in deployment | `vd run clowk-lp/web -- rails db:migrate` |
| Rollback | `vd rollback clowk-lp/web` |
| Set env var | `vd config <ref> set KEY=val` |
| List env vars | `vd config <ref> list` |
| Add SSH remote | `vd remote add prod ubuntu@host` |
| Apply to a remote | `vd apply -f voodu.hcl -r prod` |
| Install a plugin | `vd plugins:install thadeu/voodu-caddy` |

## Slash commands

Each verb has a dedicated slash command — type `/vd:<verb>` for a focused cheat sheet:

`/vd:help` `/vd:apply` `/vd:diff` `/vd:delete` `/vd:config` `/vd:logs` `/vd:exec` `/vd:run` `/vd:restart` `/vd:rollback` `/vd:release` `/vd:describe` `/vd:get` `/vd:remote` `/vd:plugins` `/vd:manifests` `/vd:patterns` `/vd:examples`

## Drilling deeper

When you need details (flags, manifest fields, end-to-end examples), open the matching file in `reference/`:

| Topic | File |
|---|---|
| `apply`, `diff`, `delete`, prune | [reference/apply.md](reference/apply.md) |
| HCL manifests — every kind | [reference/manifests.md](reference/manifests.md) |
| `config` (env vars, virtual buckets) | [reference/config.md](reference/config.md) |
| `logs`, `exec`, `run`, `restart`, `rollback`, `describe`, `get` | [reference/pods.md](reference/pods.md) |
| Remotes (multi-server SSH) | [reference/remotes.md](reference/remotes.md) |
| Plugins (caddy, postgres, redis, mongo) | [reference/plugins.md](reference/plugins.md) |
| Patterns (multi-env, shared-scope, build-mode, assets) | [reference/patterns.md](reference/patterns.md) |
| Ready-to-paste manifests | [reference/examples.md](reference/examples.md) |

## Voodu fundamentals

- **Default: upsert-only.** `vd apply` only creates/updates. To delete what disappeared from the manifest: `vd apply --prune` (opt-in, scoped by `(scope, kind)`).
- **Secrets live outside the manifest.** Use `vd config set` — its values override `env {}` blocks in HCL.
- **`scope` is a free-form grouping label.** Names are unique per scope. `deployment "clowk" "api"` is distinct from `deployment "prod" "api"`.
- **Build-mode (CWD)**: with no `image` field, voodu ships a tarball of the current directory over SSH. **Image-mode**: with `image`, the controller pulls from the registry.
- **Ports are loopback-only by default.** `ports = ["8080"]` binds `127.0.0.1:8080`. Public exposure needs an explicit IP (`0.0.0.0:8080:8080`) — but the normal path is an `ingress`.
