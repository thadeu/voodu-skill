# Remotes — multi-server

Um **remote** é só um destino SSH guardado como git remote. Não tem config file separado.

## Setup

```sh
# Bootstrap completo dum host fresh (instala + configura)
vd remote setup staging ubuntu@staging.example.com --binary ./bin/voodu

# Ou só registra um host já provisionado:
vd remote add prod-1 ubuntu@prod-1.example.com
vd remote add prod-2 ubuntu@prod-2.example.com

# Com identity file específico:
vd remote add prod ubuntu@prod.example.com:~/.ssh/prod_id_rsa
```

## Comandos

```sh
vd remote list
vd remote add NAME user@host[:identity]
vd remote remove NAME
vd remote setup NAME user@host [--binary <path>]
```

## Usar nos applies

```sh
vd apply -f voodu.hcl                  # default: git remote chamado "voodu"
vd apply -f voodu.hcl -r staging
vd apply -f voodu.hcl -r prod-1
```

`-r` é shorthand de `--remote`.

## Fan-out: deploy em N hosts

```sh
for r in prod-1 prod-2 prod-3; do
  vd apply -f voodu.hcl -r $r
done
```

Manifesto é o **mesmo** — só o `-r` muda. O scope+name no HCL é a identidade da app, igual em todo lugar.

## Quando o git remote `voodu` ajuda

Repo focado num servidor só:

```sh
git remote add voodu ssh://ubuntu@prod.example.com/~/app
```

Depois `vd apply -f voodu.hcl` sem `-r` "just works".
