---
description: vd apply -f Procfile — zero-HCL deploys, app.json, build-once, eject
---

Display the following cheat sheet to the user, verbatim, as markdown.

# `vd apply -f Procfile` — deploy a Heroku/Dokku app with zero HCL

```sh
vd apply -f Procfile             # explicit
vd apply                         # auto: ./Procfile if present, else .voodu/ manifests
vd apply -f Procfile --app ws    # pin the scope (persisted to .voodu/app.json)
vd apply -f Procfile --force     # rebuild even on a content-hash hit
vd apply -f Procfile --eject     # render to HCL (.voodu/<scope>.voodu), no server contact
```

## What each line becomes

| Procfile line | Generates |
|---|---|
| `release: <cmd>` | one-shot `job "<scope>" "release"` (runs once, gates rollout, not rollbackable) |
| `<type>: <cmd>` (any other) | `deployment "<scope>" "<type>"` — `replicas=1`, `restart="on-failure"`, `command=/bin/sh -c "<cmd>"`, `env = { PORT = "<port>" }`, `ports=["<port>"]` |

Ports auto-assign from `5000`, incrementing per deployment. Commands are shell-wrapped, so `VAR=val`, `$PORT`, `$((...))`, and pipes expand like foreman/Heroku.

```
web: env RUBYOPT="-W0" bundle exec puma -p $PORT
worker: env RUBYOPT="-W0" bundle exec sidekiq -C config/sidekiq.yml
sync: env RUBYOPT="-W0" bundle exec bin/sync
```

→ `web` on 5000, `worker` on 5001, `sync` on 5002 — three deployments, one shared image.

## Scope + routing — `.voodu/app.json`

The project-link file pins the scope and holds the ingress a Procfile can't express. **Commit it** (an uncommitted random scope double-deploys on the next machine).

```json
{
  "scope": "ws",
  "ingress": {
    "web": { "host": "app.example.com", "tls": { "enabled": true, "email": "ops@example.com" } }
  }
}
```

Ingress is keyed by process name → `ingress "<scope>" "<proc>"`; `host` required, port defaults to the process's assigned port. `${VAR}` interpolates from the scope config bucket at apply time. A Procfile **never** creates an ingress by itself.

## Config & secrets

```sh
vd config ws set RAILS_ENV=production SECRET_KEY_BASE=$(openssl rand -hex 32)
```

Scope-level config merges into every resource in the scope automatically (the `config:set` equivalent). Use this, not `env_from`.

## Build-once

All processes share one source → one image. voodu builds the first and `docker tag`s it for the rest. You'll see N tags (`<scope>-<proc>:latest` + `:<buildID>`) all pointing at **one** image ID — `docker images -q | sort -u | wc -l` = 1. Each process keeps its own tags so the reconciler and `vd rollback` work per-process.

## Gotchas

- No `statefulset` via Procfile (deployments + a release job only) — eject for stateful workloads/plugins.
- The `release:` job can't be rolled back; it runs once per apply.
- Routing only via `app.json`; `restart="on-failure"` (a clean exit 0 sits `Exited`, doesn't loop).

Full reference (incl. **Migrate from Kamal**): [reference/procfile.md](../reference/procfile.md).
