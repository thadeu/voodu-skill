---
name: voodu
description: Cheat sheet do voodu (PaaS self-hosted via HCL). Use quando o usuário pedir ajuda com comandos do voodu/vd, escrever manifestos HCL/YAML (deployment, statefulset, ingress, app, asset, job, cronjob, postgres, redis), configurar env vars, gerenciar remotes/plugins, ou perguntar "como faço X no voodu".
---

# voodu — cheat sheet

`vd` é alias do binário `voodu` (mesmo comando, escrita curta).
Esta skill é consulta rápida — sem teoria, só receitas.

## Mapa de comandos

| Quero… | Comando |
|---|---|
| Aplicar manifesto | `vd apply -f voodu.hcl` |
| Ver o que mudaria | `vd diff -f voodu.hcl` |
| Apagar recurso(s) | `vd delete <scope>/<name>` |
| Listar pods | `vd get pods` |
| Detalhe de um recurso | `vd describe deployment clowk-lp/web` |
| Logs em tempo real | `vd logs clowk-lp/web -f` |
| Entrar no container | `vd exec clowk-lp/web -- bash` |
| Restart rolling | `vd restart clowk-lp/web` |
| Stop / start | `vd stop clowk-lp/web` / `vd start clowk-lp/web` |
| Rodar job declarado | `vd run clowk-lp/migrate` |
| One-shot em deploy | `vd run clowk-lp/web rails db:migrate` |
| Rollback | `vd rollback clowk-lp/web` |
| Set/unset env var | `vd config set clowk-lp/web KEY=val` |
| Listar env vars | `vd config get clowk-lp/web` |
| Add remote SSH | `vd remote add prod ubuntu@host` |
| Aplicar em remote | `vd apply -f voodu.hcl -r prod` |
| Instalar plugin | `vd plugins:install thadeu/voodu-caddy` |

## Quando aprofundar

Quando precisar do detalhe (flags, formato do manifesto, exemplos completos), leia **só** o arquivo certo em `reference/`:

| Tópico | Arquivo |
|---|---|
| `apply`, `diff`, `delete`, prune | [reference/apply.md](reference/apply.md) |
| Manifestos HCL — todos os kinds | [reference/manifests.md](reference/manifests.md) |
| `config` (env vars) | [reference/config.md](reference/config.md) |
| `logs`, `exec`, `run`, `restart`, `rollback`, `describe`, `get` | [reference/pods.md](reference/pods.md) |
| Remotes SSH (multi-server) | [reference/remotes.md](reference/remotes.md) |
| Plugins (caddy, postgres, redis, mongo) | [reference/plugins.md](reference/plugins.md) |
| Patterns úteis (multi-env, shared-scope, build-mode, assets) | [reference/patterns.md](reference/patterns.md) |
| Exemplos prontos pra colar | [reference/examples.md](reference/examples.md) |

## Regra de ouro do voodu

- **Default: upsert-only.** `vd apply` só cria/atualiza. Pra apagar o que sumiu do manifesto: `vd apply --prune` (opt-in, por `(scope, kind)`).
- **Secrets fora do manifesto.** Use `vd config set` — vence `env {}` no HCL.
- **`scope` = etiqueta de grupo.** Nome é único por scope. `deployment "clowk" "api"` ≠ `deployment "prod" "api"`.
- **Build-mode (CWD)**: sem `image` declarado, voodu manda tarball do diretório atual via SSH. **Image-mode**: com `image`, controller dá pull do registry.
