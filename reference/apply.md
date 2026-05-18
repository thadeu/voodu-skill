# apply / diff / delete

## `vd apply` — aplicar manifesto

```sh
vd apply -f voodu.hcl                # arquivo único
vd apply -f deployments.hcl -f ingresses.hcl   # múltiplos -f
vd apply -f ./manifests/             # diretório (todos .hcl/.voodu/.yml)
vd apply -f web                      # resolve web.voodu, web.hcl, web.yml…
vd apply -f voodu.hcl -r prod        # ship pra remote "prod"
```

### Flags principais

| Flag | Pra que |
|---|---|
| `-f <arq\|dir>` | Manifesto(s). Repetível. |
| `-r <remote>` | Remote SSH (default: git remote `voodu`). |
| `--prune` | **Opt-in**. Apaga recursos do mesmo `(scope, kind)` que sumiram do manifesto. |
| `-o json` | Saída em JSON. |

### Default: upsert-only

Sem `--prune`, o `apply` só **adiciona ou atualiza** recursos — nunca apaga. Pra apagar declaradamente, pede `--prune`:

```sh
vd apply -f voodu.hcl --prune
```

Aí vira **fonte da verdade** por `(scope, kind)`:

```
Manifesto tem: deployment "clowk" "web"
Controller tem: deployment "clowk" "web" + deployment "clowk" "old"
vd apply --prune → "old" é apagado.
vd apply         → "old" continua vivo.
```

Outros kinds (ingress, statefulset) no mesmo scope ficam intactos — prune é por par `(scope, kind)`.

> Em CI, fluxo comum: `vd diff --prune` no PR pra mostrar o que sumiria; `vd apply --prune` no merge.

### Variáveis de ambiente no manifesto

Interpolação `${VAR}` e `${VAR:-default}` é resolvida na **sua máquina**, antes do tarball subir:

```hcl
deployment "clowk-lp" "web" {
  image = "ghcr.io/clowk/lp:${IMAGE_TAG:-latest}"
}
```

```sh
IMAGE_TAG=v1.4.2 vd apply -f voodu.hcl -r prod
```

## `vd diff` — preview

```sh
vd diff -f voodu.hcl
vd diff -f voodu.hcl --detailed-exitcode    # CI: 0=clean, 1=err, 2=changes
```

Saída mostra:
- `~ kind/scope/name` → vai mudar (cada linha = 1 campo)
- `+ kind/scope/name (new)` → criar
- `= kind/scope/name (unchanged)` → igual
- `--- Would prune ---` → será apagado

## `vd delete` — apagar recursos

5 formas (em ordem de uso comum):

```sh
vd delete -f voodu.hcl                       # apaga tudo do manifesto
vd delete clowk-lp/web                       # 1 recurso (auto-resolve kind)
vd delete deployment/clowk-lp/web            # 1 recurso, kind explícito
vd delete clowk-lp                           # scope inteiro
vd delete statefulset/data/pg.0              # só o pod ordinal 0
```

Pra statefulsets, `--prune` apaga **também os volumes**:

```sh
vd delete statefulset/data/pg --prune
```

Sem `--prune`, volumes ficam — você pode recriar depois mantendo os dados.

## Formato de arquivo

Tudo é HCL (ou YAML com mesmo schema). Extensões aceitas: `.hcl`, `.voodu`, `.vdu`, `.vd`, `.yml`, `.yaml`.

`vd apply -f web` resolve bare names contra essas extensões em ordem.
