---
name: voodu
description: Cheat sheet for the voodu / vd CLI (self-hosted PaaS, HCL manifests). Use whenever the user asks how to do something with voodu — running commands (apply, diff, delete, config, logs, exec, run, restart, rollback, remote, plugins), authoring HCL manifests (deployment, statefulset, ingress, app, asset, job, cronjob, registry, postgres, redis, mongo), wiring probes / init containers / autoscale / on_deploy webhooks, seeding secrets, or multi-server / shared-scope / build-mode setups.
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
| Live CPU/memory usage | `vd stats clowk-lp/web` |
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

`/vd:help` `/vd:apply` `/vd:diff` `/vd:delete` `/vd:config` `/vd:logs` `/vd:exec` `/vd:run` `/vd:restart` `/vd:rollback` `/vd:release` `/vd:describe` `/vd:get` `/vd:stats` `/vd:remote` `/vd:plugins` `/vd:manifests` `/vd:patterns` `/vd:examples`

## Drilling deeper

When you need details (flags, manifest fields, end-to-end examples), open the matching file in `reference/`:

| Topic | File |
|---|---|
| `apply`, `diff`, `delete`, prune | [reference/apply.md](reference/apply.md) |
| HCL manifests — every kind | [reference/manifests.md](reference/manifests.md) |
| `config` (env vars, virtual buckets) | [reference/config.md](reference/config.md) |
| `logs`, `exec`, `run`, `restart`, `rollback`, `describe`, `get`, `stats` | [reference/pods.md](reference/pods.md) |
| Remotes (multi-server SSH) | [reference/remotes.md](reference/remotes.md) |
| Plugins (caddy, postgres, redis, mongo) | [reference/plugins.md](reference/plugins.md) |
| Patterns (multi-env, shared-scope, build-mode, assets) | [reference/patterns.md](reference/patterns.md) |
| Ready-to-paste manifests | [reference/examples.md](reference/examples.md) |

## Voodu fundamentals

- **HCL is the only input format.** YAML input was removed in beta. Accepted extensions: `.hcl`, `.voodu`, `.vdu`, `.vd`. (`yaml:` struct tags remain only for `vd describe -o yaml` output formatting.)
- **Default: upsert-only.** `vd apply` only creates/updates. To delete what disappeared from the manifest: `vd apply --prune` (opt-in, scoped by `(scope, kind)`).
- **Secrets live outside the manifest.** Use `vd config set` — its values override `env {}` blocks in HCL.
- **`scope` is a free-form grouping label.** Names are unique per scope. `deployment "clowk" "api"` is distinct from `deployment "prod" "api"`.
- **Image-mode vs build-mode.** `image = "..."` and `build { ... }` are mutually exclusive (parse error if both). With `image`, the controller pulls from the registry. With `build { context = "..." }`, the CLI tarballs the working tree over SSH. Omitting both gives auto-detect at repo root. The `build {}` block is docker-compose-shaped (`context`, `dockerfile`, `args`, nested `lang {}`).
- **`env_from = ["scope/name"]` does two things:** (1) at **runtime**, stacks the bucket's env file under the resource's own env (operator's `env {}` wins on collisions). (2) at **parse-time** (CLI-side), feeds the same bucket into `${VAR}` interpolation so manifests can reference secrets stored centrally on the controller. Shell env still wins over the bucket on collision — ad-hoc override works. Supported on `deployment`, `app`, `statefulset`, `job`, `cronjob`.
- **Probes (kubelet-style).** `probes { liveness { ... } readiness { ... } startup { ... } }` on `deployment` / `app` / `statefulset`. Selectors: `http_get`, `tcp_socket`, `exec`. Liveness fails → docker restart. Readiness fails → upstream removed from caddy ingress automatically. Startup gates readiness until the first pass. See [reference/manifests.md](reference/manifests.md).
- **Init containers.** `init "<name>" { command = [...] }` declares ordered one-shot prep steps that must exit 0 before the main container starts. Runs per-replica spawn; inherits env / volumes / networks / env_from from the parent.
- **TLS defaults.** Declaring `tls {}` on an ingress (even bare) flips `enabled = true` and `provider = "letsencrypt"`. Omit the entire block to disable TLS. Override `provider = "internal"` for dev/staging self-signed.
- **Ports are loopback-only by default.** `ports = ["8080"]` binds `127.0.0.1:8080`. Public exposure needs an explicit IP (`0.0.0.0:8080:8080`) — but the normal path is an `ingress`.
- **Private registries.** Declare `registry "ghcr" { url, username, token }` ONCE per host — voodu regenerates `~/.docker/config.json` atomically. Use a service-account / bot token (one-credential-per-host constraint — see [reference/manifests.md](reference/manifests.md)).
