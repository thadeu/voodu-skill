# GitHub Actions — deploy from CI

The official action is [`clowk-in/voodu-gh`](https://github.com/clowk-in/voodu-gh). It installs the CLI, prepares SSH, and runs `vd apply` — the same command an operator runs locally. There is no separate CI protocol.

## Minimal workflow

```yaml
name: deploy

on:
  push:
    branches: [main]
    tags: ['v*']

env:
  VOODU_HOST:        ${{ secrets.VOODU_HOST }}
  VOODU_SSH_KEY:     ${{ secrets.VOODU_SSH_KEY }}
  VOODU_KNOWN_HOSTS: ${{ secrets.VOODU_KNOWN_HOSTS }}
  VOODU_VERSION:     v0.9.3

concurrency:
  group: voodu-deploy-production
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - uses: clowk-in/voodu-gh@v1
        with:
          manifests: |
            infra/web.voodu
            infra/pwa.voodu
```

## Inputs

Every input falls back to an env var, so shared values are declared **once** at workflow level and each `uses:` carries only what differs. An explicit `with:` wins over the environment.

| Input | Env fallback | Default | Notes |
|---|---|---|---|
| `manifests` | `VOODU_MANIFESTS` | — | One per line (commas ok). File, directory, or glob. |
| `host` | `VOODU_HOST` | — | `user@hostname`, or bare hostname with `user` set. |
| `user` | `VOODU_USER` | — | Lets only the address be a secret. |
| `ssh-key` | `VOODU_SSH_KEY` | — | Private key. |
| `known-hosts` | `VOODU_KNOWN_HOSTS` | — | From `ssh-keyscan -H <host>`. |
| `port` | `VOODU_PORT` | `22` | Never put the port in `host`. |
| `version` | `VOODU_VERSION` | latest | Pin it. |
| `working-directory` | `VOODU_WORKDIR` | `.` | For monorepos. |
| `remote-name` | `VOODU_REMOTE_NAME` | `voodu` | |
| `dry-run` | `VOODU_DRY_RUN` | `false` | Runs `vd diff` instead. |
| `cache` | `VOODU_CACHE` | `true` | Caches the CLI per exact release. |

## Several manifests, several servers

All manifests in one step go into **one** `vd apply` as a repeatable `-f`, so they share a single plan. Prefer that over several steps when the target is the same host.

```yaml
      - uses: clowk-in/voodu-gh@v1
        with: { manifests: "infra/web.voodu\ninfra/pwa.voodu" }
```

Use separate steps for **different** hosts, overriding just the target:

```yaml
      - uses: clowk-in/voodu-gh@v1
        with:
          host: ${{ secrets.VOODU_HOST_EU }}
          known-hosts: ${{ secrets.VOODU_KNOWN_HOSTS_EU }}
          manifests: infra/eu.voodu
```

## Plan on pull requests

```yaml
on: [pull_request]

concurrency:
  group: voodu-plan-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: clowk-in/voodu-gh@v1
        with:
          manifests: infra/web.voodu
          dry-run: true
```

The plan is computed against the PR's **merge commit** — `actions/checkout`'s default on that event.

## Pin the image to the commit

Registry-mode apply does **not** re-pull a moving tag, so `:latest` can deploy nothing. Manifests interpolate `${VAR}` from the environment:

```yaml
      - uses: clowk-in/voodu-gh@v1
        env:
          IMAGE_TAG: ${{ github.sha }}
        with: { manifests: infra/web.voodu }
```

## Gotchas

- **`actions/checkout` is required.** Voodu resolves its SSH target by reading a git remote (`git remote get-url voodu`), so the workspace must be a git repo. The action writes that remote itself — never add it by hand in the workflow.
- **Never `cancel-in-progress: true` on a job that applies.** The reconciler runs async to apply, so cancelling drops the SSH connection while the server keeps going. Queueing is correct: GitHub keeps one pending run per group and cancels the previous pending one, so rapid pushes collapse to "finish current, apply newest".
- **Group by target, not by branch.** The point is serialising everything aimed at the same server.
- **No `--prune` from CI.** It is opt-in by default; keep it that way.
- **The server records no commit.** Build ids are content hashes, so an unchanged context skips the rebuild (`VOODU_FORCE_REBUILD` overrides), and there is no rollback-by-commit. Traceability comes from the image tag.
- **Not in the build context, ever:** `.git`, `.gitignore`, `node_modules`, `.voodu`, `.DS_Store`. Beyond that `.dockerignore` rules, and when present it **replaces** `.gitignore` entirely. Submodules need `submodules: true` on checkout.

## Security

The action carries an SSH key with shell access, and the deploy user is in the `docker` group — root in practice. Mitigate on the server, not in the workflow:

- Pin `known-hosts`. Without it the action warns and accepts any host key, which on an ephemeral runner means every run.
- Forced command in the server's `authorized_keys`:
  `command="voodu $SSH_ORIGINAL_COMMAND",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding ssh-ed25519 AAAA...`
- Put the human gate on a GitHub Environment with required reviewers — approval is always implied at the CLI level.
- Pin the action by commit SHA in sensitive repos; `@v1` is a movable tag.

## Versioning

`@v1.1.0` is immutable, `@v1` follows compatible releases, `@<full sha>` is unforgeable.
