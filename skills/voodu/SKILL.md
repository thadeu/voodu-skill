---
name: voodu
description: Cheat sheet for the voodu / vd CLI (self-hosted PaaS, HCL manifests). Use whenever the user asks how to do something with voodu — running commands (apply, diff, delete, config, logs, exec, run, restart, rollback, remote, plugins), authoring HCL manifests (deployment, statefulset, ingress, app, asset, job, cronjob, registry, postgres, redis, mongo), wiring probes / init containers / autoscale / on_deploy + on_probe webhooks, seeding secrets, multi-server / shared-scope / build-mode setups, or deploying from CI with the GitHub Action (clowk-in/voodu-gh).
---

# voodu — cheat sheet

`vd` is an alias for the `voodu` binary (same command, shorter spelling).
This skill is a quick-reference for authoring `.voodu` HCL manifests and answering
voodu questions — no theory, just recipes. Drill into `reference/` for the full detail.

## Official docs

- **Full documentation:** https://voodu.clowk.in/docs/
- **LLM reference (`llm.txt`):** https://voodu.clowk.in/llm.txt — fetch this for the
  complete, authoritative, up-to-date surface when the recipes here aren't enough.

## Command map

| I want to… | Command |
|---|---|
| Apply a manifest | `vd apply -f voodu.hcl` |
| Deploy a Heroku/Dokku Procfile (zero HCL) | `vd apply -f Procfile` |
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
| Deploy from GitHub Actions | `uses: clowk-in/voodu-gh@v1` |

## Drilling deeper

When you need details (flags, manifest fields, end-to-end examples), open the matching file in `reference/`:

| Topic | File |
|---|---|
| HCL manifests — every kind | [reference/manifests.md](reference/manifests.md) |
| Ready-to-paste manifests | [reference/examples.md](reference/examples.md) |
| Patterns (multi-env, shared-scope, build-mode, assets) | [reference/patterns.md](reference/patterns.md) |
| `vd apply` (+ `--prune`) | [reference/apply.md](reference/apply.md) |
| `vd diff` | [reference/diff.md](reference/diff.md) |
| `vd delete` | [reference/delete.md](reference/delete.md) |
| `vd config` (env vars, virtual buckets) | [reference/config.md](reference/config.md) |
| `vd logs` | [reference/logs.md](reference/logs.md) |
| `vd exec` | [reference/exec.md](reference/exec.md) |
| `vd run` | [reference/run.md](reference/run.md) |
| `vd restart` / `stop` / `start` | [reference/restart.md](reference/restart.md) |
| `vd rollback` | [reference/rollback.md](reference/rollback.md) |
| `vd release` | [reference/release.md](reference/release.md) |
| `vd describe` | [reference/describe.md](reference/describe.md) |
| `vd get` | [reference/get.md](reference/get.md) |
| `vd stats` | [reference/stats.md](reference/stats.md) |
| `vd remote` (multi-server SSH) | [reference/remote.md](reference/remote.md) |
| `vd plugins` (caddy, postgres, redis, mongo) | [reference/plugins.md](reference/plugins.md) |
| Procfile mode + migrate from Heroku/Dokku/Kamal | [reference/procfile.md](reference/procfile.md) |
| Deploy from GitHub Actions (`clowk-in/voodu-gh`) | [reference/github-actions.md](reference/github-actions.md) |

## Voodu fundamentals

- **HCL is the only input format.** YAML input was removed in beta. Accepted extensions: `.hcl`, `.voodu`, `.vdu`, `.vd`. (`yaml:` struct tags remain only for `vd describe -o yaml` output formatting.)
- **Procfile is the zero-HCL on-ramp.** `vd apply -f Procfile` reads a Heroku/Dokku-style `type: command` file and generates one `deployment` per line (a `job` for `release:`), auto-detects the language, and **builds once** (the processes share one source → one image, retagged per process). Routing/scope live in `.voodu/app.json` (commit it); `vd config <scope> set` is the `config:set` equivalent; `--eject` graduates the Procfile to HCL. Full reference + Kamal migration: [reference/procfile.md](reference/procfile.md).
- **Default: upsert-only.** `vd apply` only creates/updates. To delete what disappeared from the manifest: `vd apply --prune` (opt-in, scoped by `(scope, kind)`).
- **Secrets live outside the manifest.** Use `vd config set` — its values override `env {}` blocks in HCL.
- **`scope` is a free-form grouping label.** Names are unique per scope. `deployment "clowk" "api"` is distinct from `deployment "prod" "api"`.
- **Image-mode vs build-mode.** `image = "..."` and `build { ... }` are mutually exclusive (parse error if both). With `image`, the controller pulls from the registry. With `build { context = "..." }`, the CLI tarballs the working tree over SSH. Omitting both gives auto-detect at repo root. The `build {}` block is docker-compose-shaped (`context`, `dockerfile`, `args`, nested `lang {}`).
- **`env_from = ["scope/name"]` does two things:** (1) at **runtime**, stacks the bucket's env file under the resource's own env (operator's `env {}` wins on collisions). (2) at **parse-time** (CLI-side), feeds the same bucket into `${VAR}` interpolation so manifests can reference secrets stored centrally on the controller. Shell env still wins over the bucket on collision — ad-hoc override works. Supported on `deployment`, `app`, `statefulset`, `job`, `cronjob`.
- **Probes (kubelet-style).** `probes { liveness { ... } readiness { ... } startup { ... } }` on `deployment` / `app` / `statefulset`. Selectors: `http_get`, `tcp_socket`, `exec`. Liveness fails → docker restart. Readiness fails → upstream removed from caddy ingress automatically. Startup gates readiness until the first pass. See [reference/manifests.md](reference/manifests.md).
- **Runtime-health webhooks (`on_probe`).** Sibling of `on_deploy` for live pod health. `on_probe { failure { url = "..." } recovery { url = "..." } }` fires when a probe transitions — Telegram / Slack / PagerDuty in parallel. Tokens: `{{pod}}`, `{{probe}}`, `{{transition}}`, `{{reason}}`, `{{transition_id}}` (deterministic dedup key). Suppressed during planned teardown (rolling restart, scale-down, `vd restart`). Works on `deployment`, `statefulset`, and plugin-expanded kinds (postgres, redis, mongo).
- **Init containers.** `init "<name>" { command = [...] }` declares ordered one-shot prep steps that must exit 0 before the main container starts. Runs per-replica spawn; inherits env / volumes / networks / env_from from the parent.
- **TLS defaults.** Declaring `tls {}` on an ingress (even bare) flips `enabled = true` and `provider = "letsencrypt"`. Omit the entire block to disable TLS. Override `provider = "internal"` for dev/staging self-signed.
- **Ports are loopback-only by default.** `ports = ["8080"]` binds `127.0.0.1:8080`. Public exposure needs an explicit IP (`0.0.0.0:8080:8080`) — but the normal path is an `ingress`.
- **Deploying from CI is the same `vd apply`.** The [`clowk-in/voodu-gh`](https://github.com/clowk-in/voodu-gh) action installs the CLI, prepares SSH, and calls `vd apply -y`. Two things bite people: `actions/checkout` is mandatory (voodu resolves its SSH target through a git remote, which the action writes itself), and a job that applies must NOT use `cancel-in-progress: true` — the reconciler runs async, so cancelling leaves a half-applied release racing a newer one. Full recipe: [reference/github-actions.md](reference/github-actions.md).
- **Private registries.** Declare `registry "ghcr" { url, username, token }` ONCE per host — voodu regenerates `~/.docker/config.json` atomically. Use a service-account / bot token (one-credential-per-host constraint — see [reference/manifests.md](reference/manifests.md)).
