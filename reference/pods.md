# pods / logs / exec / run / restart / rollback

## `vd get pods` — listar containers

```sh
vd get pods                        # tudo
vd get pods -s clowk-lp            # scope
vd get pods clowk-lp/web           # 1 recurso (todas as réplicas)
vd get pods -o json                # programático
```

## `vd describe <kind> <ref>` — detalhe completo

```sh
vd describe deployment clowk-lp/web    # manifest + status + pods
vd describe statefulset data/pg
vd describe ingress clowk-lp/web
```

`vd get pod <ref>` é alias de `vd describe pod`.

## `vd logs` — stream de logs

```sh
vd logs clowk-lp/web                   # todas réplicas, modo follow
vd logs clowk-lp/web -f                # explicit follow
vd logs clowk-lp/web --tail 100        # últimas 100 linhas
vd logs clowk-lp -f                    # scope inteiro (multiplex)
vd logs clowk-lp-web.abc123            # 1 container específico
```

stdout e stderr vêm mergeados (foi feature recente).

## `vd exec` — entrar no container

```sh
vd exec clowk-lp/web -- bash           # auto-pick best replica
vd exec clowk-lp/web -- ls -la /app
vd exec clowk-lp-web.abc123 -- sh      # container específico
```

Sem flags, voodu auto-detecta TTY/stdin. Pra workdir/user específicos, flags equivalentes ao `docker exec`.

## `vd run` — one-shot

Verbo unificado. 3 comportamentos pela forma do ref:

```sh
# 1. Job declarado → trigger único
vd run clowk-lp/migrate

# 2. Cronjob declarado → force-tick (ignora schedule)
vd run clowk-lp/nightly-backup

# 3. Deployment + command → exec one-shot
vd run clowk-lp/web -- rails db:migrate
vd run clowk-lp/web -- rake clean
```

Sem command, só funciona em `job` ou `cronjob` (recursos com "trigger me once").

Diferença prática:
- `vd exec` — entra num container vivo (mesma máquina existente).
- `vd run` (com cmd) — spawn um container fresh com o spec do recurso.
- `vd apply` — desired state.

## `vd restart` — rolling restart

```sh
vd restart clowk-lp/web                # deployment ou statefulset
```

Não muda manifesto, só recria containers.
Útil pra pegar nova versão duma imagem com tag mutável (`:latest`), recarregar env, etc.

## `vd stop` / `vd start`

```sh
vd stop clowk-lp/web                   # todas réplicas
vd stop clowk-lp/web.0                 # só ordinal 0 (statefulset)
vd start clowk-lp/web                  # destrava + recria
```

`stop` marca o recurso como freezed — re-apply não recria. `start` libera.

## `vd rollback` — voltar release

```sh
vd rollback clowk-lp/web               # release anterior
vd rollback clowk-lp/web release-42    # release específico
```

Re-aplica snapshot da spec dum release passado. Histórico é mantido até `keep_releases` (default ~10).

## `vd release` — re-disparar release phase

```sh
vd release clowk-lp/web                # roda release_command de novo
vd release clowk-lp/web list           # lista releases
```

Útil quando o `release { command = ... }` falhou e você quer re-rodar sem novo deploy.
