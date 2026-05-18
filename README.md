# voodu-claudekit

Claude Code skill para consulta rápida do CLI `voodu` / `vd`.

Sem teoria, sem reler README do voodu cada vez que esqueci o nome dum comando. Mapa de comandos + manifestos HCL + patterns prontos pra colar.

## O que tem aqui

- `SKILL.md` — entry point com mapa de comandos
- `reference/apply.md` — `apply`, `diff`, `delete`, prune
- `reference/manifests.md` — todos os kinds HCL (deployment, statefulset, ingress, app, asset, job, cronjob, postgres, redis)
- `reference/config.md` — `vd config` (env vars, buckets virtuais)
- `reference/pods.md` — `logs`, `exec`, `run`, `restart`, `rollback`, `describe`, `get`
- `reference/remotes.md` — multi-server via SSH
- `reference/plugins.md` — plugins oficiais (caddy, postgres, redis, mongo)
- `reference/patterns.md` — multi-env, shared-scope, assets, build-mode
- `reference/examples.md` — manifestos prontos

## Instalação

### Como submodule (recomendado)

```sh
cd ~/.claude/skills
git submodule add https://github.com/thadeu/voodu-claudekit voodu
```

Próxima vez que abrir o Claude Code, ele detecta `~/.claude/skills/voodu/SKILL.md` e ativa quando você perguntar sobre voodu.

### Como clone simples

```sh
git clone https://github.com/thadeu/voodu-claudekit ~/.claude/skills/voodu
```

### Update

```sh
cd ~/.claude/skills/voodu
git pull
```

Submodule:

```sh
cd ~/.claude
git submodule update --remote skills/voodu
```

## Como o Claude usa

Quando você perguntar coisas tipo:

- "Como apago um deployment no voodu?"
- "Qual a sintaxe pra cronjob?"
- "Tenho um app Rails, monta um manifesto"
- "Como rodo migration?"

O Claude carrega o `SKILL.md`, vê o mapa, e abre só o arquivo de referência relevante (não joga 8 docs no contexto).

## Voodu

Projeto: https://github.com/thadeu/clowk-voodu

## License

MIT
