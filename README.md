# voodu-claudekit

Claude Code skill + slash commands for the [voodu](https://github.com/thadeu/clowk-voodu) CLI.

Stop re-reading the voodu README every time you forget a flag. Type `/vd:apply` (or `/vd:config`, `/vd:logs`, etc.) and get a focused cheat sheet right inside Claude Code.

## What's in here

- **`SKILL.md`** — skill entry point. Index of commands + voodu fundamentals.
- **`reference/`** — deep-dive docs (loaded by the agent when it needs more context).
  - `apply.md` — `apply`, `diff`, `delete`, prune semantics
  - `manifests.md` — every HCL kind (deployment, statefulset, ingress, app, asset, job, cronjob, postgres, redis, mongo)
  - `config.md` — `vd config` (env vars, virtual buckets)
  - `pods.md` — `logs`, `exec`, `run`, `restart`, `rollback`, `describe`, `get`
  - `remotes.md` — multi-server SSH
  - `plugins.md` — official plugins (caddy, postgres, redis, mongo)
  - `patterns.md` — multi-env, shared-scope, build-mode, assets, secret seeding
  - `examples.md` — ready-to-paste manifests
- **`commands/`** — slash commands. One file per verb (`apply.md`, `diff.md`, ...) — typing `/vd:apply` displays the matching cheat sheet.

## Install

### Option A — `install.sh` (recommended)

```sh
git clone https://github.com/thadeu/voodu-claudekit ~/code/voodu-claudekit
~/code/voodu-claudekit/install.sh
```

The script symlinks:

- `~/.claude/skills/voodu` → repo root (skill discovery)
- `~/.claude/commands/vd` → `repo/commands` (slash command namespace)

### Option B — git submodule

```sh
cd ~/.claude
git submodule add https://github.com/thadeu/voodu-claudekit skills/voodu
ln -s skills/voodu/commands commands/vd
```

### Update

```sh
cd ~/.claude/skills/voodu && git pull
```

Or with submodules:

```sh
cd ~/.claude && git submodule update --remote skills/voodu
```

## Usage

Once installed, open Claude Code in any project. Try:

- `/vd:help` — index of every slash command
- `/vd:apply` — apply / flags / examples
- `/vd:config` — env-var management
- `/vd:logs`, `/vd:exec`, `/vd:run`, `/vd:restart` — runtime ops
- `/vd:manifests` — every HCL kind
- `/vd:patterns` — multi-env, shared-scope, build-mode
- `/vd:examples` — copy-paste-ready manifests

The skill itself also fires automatically when you ask questions like "how do I roll back a deployment in voodu?" — Claude loads `SKILL.md` and pulls the matching reference doc.

## Voodu

Project: https://github.com/thadeu/clowk-voodu

## License

MIT
