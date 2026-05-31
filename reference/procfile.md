# Procfile mode

Deploy a Heroku/Dokku/foreman app with zero HCL. `vd apply -f Procfile` ships the Procfile's **directory** as a tarball to the controller, which reads the Procfile, generates manifests, builds the source, and applies.

```sh
vd apply -f Procfile            # explicit
vd apply                        # auto: ./Procfile if present, else .voodu/ manifests
```

What it generates from a Procfile:

- `release:` line → a one-shot `job "<scope>" "release"` (runs once per apply, gates the rollout).
- every other line → a long-running `deployment "<scope>" "<type>"`: `replicas=1`, `restart="on-failure"`, `command=/bin/sh -c "<raw command>"`, `env = { PORT = "<port>" }`, `ports=["<port>"]`.
- ports auto-assigned from `5000`, incrementing per deployment. An app.json ingress that names a port **pins** it (PORT env + published + ingress agree) and does NOT consume an auto slot.
- commands are shell-wrapped (`/bin/sh -c`) so `VAR=val` prefixes, `$PORT`, `$((...))`, pipes expand like Heroku/foreman.
- routing is NEVER created from the Procfile — only from app.json ingress entries.

Procfile syntax: `type: command` lines. Blank lines and `#` comments ignored. Duplicate process types rejected. Empty Procfile rejected. Type must match `^[A-Za-z][A-Za-z0-9_-]*$`.

Realistic Rails Procfile (scope `ws`):

```
web: env RUBYOPT="-W0" bundle exec puma -p $PORT
worker: env RUBYOPT="-W0" bundle exec sidekiq -C config/sidekiq.yml
sync: env RUBYOPT="-W0" bundle exec bin/sync
```

→ `web` deployment on 5000, `worker` on 5001, `sync` on 5002. No ingress yet (add it in app.json).

## The mapping

| Procfile line | Generates | Notes |
|---|---|---|
| `release: <cmd>` | `job "<scope>" "release"` | one-shot, runs once per apply, gates rollout, NOT rollbackable |
| `web: <cmd>` (any non-release) | `deployment "<scope>" "web"` | `replicas=1`, `restart="on-failure"`, `command=/bin/sh -c "<cmd>"` |
| (per deployment) | `env = { PORT = "<port>" }` + `ports=["<port>"]` | auto from 5000++ unless app.json pins it |
| app.json `ingress.<proc>` | `ingress "<scope>" "<proc>"` | routes to that proc's deployment; host REQUIRED |

`restart="on-failure"` (NOT HCL default `unless-stopped`): a deliberate exit-0 (a misplaced one-shot) sits `Exited` instead of looping.

Build: the per-process command lives on the **manifest**, not baked into the image. Spec is nil → the build pipeline auto-detects the language from the source tree (Ruby/Rails, Python, Node, Go — same auto-detect as HCL build-mode). All processes share ONE source tree → ONE runtime image.

## Scope + .voodu/app.json

`.voodu/app.json` is the project-link file — pins the scope and holds per-process ingress a Procfile can't express. Same idea as Vercel's `.vercel/project.json`. **Commit it.**

```json
{
  "scope": "ws",
  "ingress": {
    "web": {
      "host": "ws.example.com",
      "tls": { "enabled": true, "email": "ops@example.com" }
    }
  }
}
```

Ingress is keyed by **process name** → emits `ingress "<scope>" "<proc>"` routing to that process's deployment. `port` defaults to that process's assigned port. `host` is REQUIRED. Optional: `service`, `port`, `tls`, `lb`, `location { path, strip_prefix }`, `locations [ ... ]`.

`${VAR}` in app.json interpolates from the scope config bucket at apply time — one app.json serves multiple stages (set the var per server with `vd config <scope> set`):

```json
{ "scope": "ws", "ingress": { "web": { "host": "${APP_HOST}" } } }
```

```sh
vd config ws set APP_HOST=staging.example.com   # on staging
vd config ws set APP_HOST=ws.example.com        # on prod
```

Scope identity rules (stable across applies → re-apply is idempotent, no duplicate pods):

- `--app <name>` → use it AND persist to `.voodu/app.json`.
- else `.voodu/app.json` exists → reuse its scope.
- else → generate a random 3-char scope AND write `.voodu/app.json`. Random (not derived from dirname) avoids collisions. Commit it, or pass `--app` to pin.

`.voodu/` is excluded from the build context EXCEPT `app.json` (re-included so the server reads ingress).

## Config / secrets

Heroku `config:set` equivalent — scope-level config merges into EVERY resource in the scope automatically (the reconciler builds each deployment's env = scope-level + app-level):

```sh
vd config ws set RAILS_ENV=production SECRET_KEY_BASE=$(openssl rand -hex 32)
vd config ws set DATABASE_URL="postgres://..."
vd config ws get          # substring filter, not exact match
```

Use `vd config <scope> set`, NOT `env_from`. `env_from` would duplicate the merge and hard-fail if the bucket doesn't exist yet.

## Build-once

Because all processes share one source → one image, voodu builds the **first** process and `docker tag`s that image for the others instead of rebuilding N times. Result: N tags (each `<scope>-<proc>:latest` AND `<scope>-<proc>:<buildID>`) ALL pointing at ONE image ID — shared storage, not N×size. Each process still gets its own tags so the reconciler (resolves `<scope>-<proc>:latest` per resource) and rollback (needs per-process `:<buildID>`) work independently. `docker images` lists one row per tag repeating the size — looks like N images but `docker images -q | sort -u | wc -l` = 1. Force a rebuild on a content-hash hit with `--force` (or `VOODU_FORCE_REBUILD=1`).

## Eject to HCL

Graduate to full HCL control. Renders the Procfile to HCL with a commented ingress stub, NO server contact:

```sh
vd apply -f Procfile --eject     # writes .voodu/<scope>.voodu, exits
vd apply -f <scope>              # re-apply the generated HCL
```

After ejecting you own the HCL — add statefulsets, plugins, ingress, probes, etc. that Procfile mode can't express.

## Migrate from Heroku / Dokku

1. Drop your existing `Procfile` in the repo root (it already works as-is).
2. `vd config <scope> set` every Heroku `config:set` var (`DATABASE_URL`, `SECRET_KEY_BASE`, etc.).
3. Add routing in `.voodu/app.json` → `ingress.web.host` (+ `tls`). Procfile alone never creates an ingress.
4. `vd apply -f Procfile`. Commit `.voodu/app.json` so the scope + routing stay stable across machines/CI.

Scale a process: eject and bump `replicas`, or keep on `replicas=1` (Procfile default). Stateful add-ons (Postgres/Redis) require HCL → eject and declare the plugins.

## Migrate from Kamal

Kamal config is `config/deploy.yml` (imperative, CLI orchestrates SSH). voodu is declarative — HCL is desired state, a controller reconciles. No k8s either side; both use SSH + docker.

| `config/deploy.yml` | voodu |
|---|---|
| `service` + `image` | `deployment "<scope>" "web" { image = "..." }` (or `build {}`) |
| `servers.web.hosts: [...]` | `vd remote add ...` per host + `replicas` for scale; each ROLE = its own deployment |
| `servers.job: { cmd: "bin/jobs" }` | long-running worker `deployment` (via `command`) or a `cronjob` |
| `registry: { server, username, password: <ENV> }` | `registry "<name>" { url, username, token }` |
| `env.clear: { K: v }` | `env = {}` in HCL, or `vd config set` |
| `env.secret: [NAMES]` (.kamal/secrets) | `vd config <ref> set KEY=val` (secrets live OUTSIDE the manifest, override `env = {}`) |
| `proxy: { ssl: true, host: app.example.com }` | `ingress "<scope>" "web" { host = "..." tls { email = "..." } }` |
| `accessories.db: { image: postgres:16 }` | `postgres "<scope>" "db" {}` (voodu-postgres plugin) |
| `accessories.redis: { image: redis }` | `redis "<scope>" "cache" {}` (voodu-redis plugin) |
| `builder: { arch, dockerfile, context, args }` | `build { context, dockerfile, args, lang {} }` |

Command cheatsheet:

| Kamal | voodu |
|---|---|
| `kamal setup` / `kamal deploy` | `vd apply -f voodu.hcl -r prod` |
| `kamal rollback` | `vd rollback <scope>/web` |
| `kamal app exec 'CMD'` | `vd exec <ref> -- CMD` or `vd run <ref> -- CMD` |
| `kamal accessory boot db` | declare `postgres {}` and apply |
| migrations (pre-deploy hook / `app exec rails db:migrate`) | `release { command = ["bin/rails","db:migrate"] }` (runs once per release, gates rollout) |

Conceptual differences to call out: Kamal accessories are sidecars you boot; voodu stateful services are plugin-managed first-class resources. Kamal has no controller; voodu runs one per host.

## Gotchas

- **No statefulset via Procfile** — deployments + a release job only. For Postgres/Redis/any stateful service, eject to HCL and declare the plugins.
- **release job has no rollback** — rollback is deployment/statefulset only. `release:` runs once per apply (one-shot, not recurring).
- **Routing only via app.json** — the Procfile NEVER creates an ingress. Host/TLS live in `.voodu/app.json` ingress entries (keyed by process name), or you eject to HCL.
- **`restart="on-failure"`** (not HCL's `unless-stopped`) — a process that exits 0 sits `Exited`, doesn't loop. A worker that's supposed to stay up must not exit cleanly.
- **`vd config <scope> set`, not `env_from`** — scope config auto-merges into every resource; `env_from` duplicates the merge and hard-fails on a missing bucket.
- **Commit `.voodu/app.json`** — an uncommitted random scope means the next machine/CI run generates a *different* scope and double-deploys. Pin with `--app` or commit the file.

See also: `manifests.md` (HCL kinds), `apply.md` (apply flags + prune), `config.md` (buckets), `patterns.md` (multi-env, build-mode, secrets), `plugins.md` (postgres/redis).
