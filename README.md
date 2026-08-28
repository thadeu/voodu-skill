# voodu-skill

Agent skill for the [voodu](https://github.com/thadeu/clowk-voodu) / `vd` CLI — a reference
that helps your agent author `.voodu` HCL manifests and answer voodu questions.

Ask "write a voodu statefulset for postgres" or "migrate this Kamal app to voodu" and the
agent loads the skill and pulls the matching reference doc.

Works with **Claude Code, Codex, Cursor**, and any agent supported by [`npx skills`](https://github.com/vercel-labs/skills).

## Docs

- Full documentation: https://voodu.clowk.in/docs/
- LLM reference (`llm.txt`): https://voodu.clowk.in/llm.txt

## Install

### Recommended — `npx skills` (any agent)

```sh
npx skills add thadeu/voodu-skill                 # interactive — pick your agent(s)

npx skills add thadeu/voodu-skill -a claude-code  # Claude Code
npx skills add thadeu/voodu-skill -a codex        # Codex
npx skills add thadeu/voodu-skill -a cursor       # Cursor

npx skills add thadeu/voodu-skill -g              # global (~/) instead of the project
npx skills add thadeu/voodu-skill -y              # non-interactive
```

The full GitHub URL works too: `npx skills add https://github.com/thadeu/voodu-skill`.

### Claude Code — `install.sh`

Symlinks the skill into `~/.claude/skills/voodu`:

```sh
git clone https://github.com/thadeu/voodu-skill ~/code/voodu-skill
~/code/voodu-skill/install.sh
```

### Update

```sh
npx skills add thadeu/voodu-skill -y      # re-run to pull the latest
# or, if installed via install.sh:
cd ~/code/voodu-skill && git pull
```

## What's in here

The skill lives in **`skills/voodu/`** (the standard layout — it lets `npx skills` bundle
`SKILL.md` together with its `reference/` docs):

- **`skills/voodu/SKILL.md`** — entry point. Command map, voodu fundamentals, and links to
  the official docs + `reference/`. Loaded automatically when you ask a voodu question.
- **`skills/voodu/reference/`** — deep-dive docs, pulled in when more context is needed.
  - **Authoring:** `manifests.md` (every HCL kind), `examples.md` (ready-to-paste), `patterns.md` (multi-env, shared-scope, build-mode, assets)
  - **CLI, one file per verb:** `apply.md`, `diff.md`, `delete.md`, `config.md`, `logs.md`, `exec.md`, `run.md`, `restart.md`, `rollback.md`, `release.md`, `describe.md`, `get.md`, `stats.md`, `remote.md`, `plugins.md`, `procfile.md`
  - **CI:** `github-actions.md` (the `clowk-in/voodu-gh` action — inputs, plan-on-PR, concurrency, and the SSH key's blast radius)

## Usage

Ask in plain language — "how do I roll back a deployment in voodu?", "write a statefulset
for postgres", "migrate this Kamal app to voodu", "deploy this repo from GitHub Actions" —
and the agent loads `SKILL.md` and pulls the matching reference doc.

## Voodu

Project: https://github.com/thadeu/clowk-voodu

## License

MIT
