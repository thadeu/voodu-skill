# `vd remote` — SSH targets

A **remote** is just an SSH target stored as a git remote. No separate config file.

## Setup

```sh
# Full bootstrap of a fresh host (install + configure)
vd remote setup staging ubuntu@staging.example.com --binary ./bin/voodu

# Or register an already-provisioned host:
vd remote add prod-1 ubuntu@prod-1.example.com

# With a specific identity file:
vd remote add prod ubuntu@prod.example.com:~/.ssh/prod_id_rsa
```

## Commands

```sh
vd remote list
vd remote add NAME user@host[:identity]
vd remote remove NAME
vd remote setup NAME user@host [--binary <path>]
```

## Use in applies

```sh
vd apply -f voodu.hcl                  # default: git remote named "voodu"
vd apply -f voodu.hcl -r staging
vd apply -f voodu.hcl -r prod-1
```

`-r` is shorthand for `--remote`.

## Fan-out across many hosts

```sh
for r in prod-1 prod-2 prod-3; do
  vd apply -f voodu.hcl -r $r
done
```

The manifest is **identical** — only `-r` changes. Scope+name is the app identity, stable across every environment.

## When the `voodu` git remote helps

```sh
git remote add voodu ssh://ubuntu@prod.example.com/~/app
```

After that, `vd apply -f voodu.hcl` with no `-r` "just works" against that host.
