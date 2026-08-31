# `drain {}` and plugin blocks — rollouts that don't cut work

## The first thing to check

Voodu already sends SIGTERM before removing a container: `Containers.Remove`
runs `docker stop` before `rm -f`, which gives the process docker's default
**10 seconds**.

So an app that loses work on deploy has one of three problems, and none of
them is a load balancer:

- it ignores SIGTERM and only dies on SIGKILL
- it is not PID 1 (an entrypoint wrapped in `sh -c` swallows the signal)
- it genuinely needs longer than 10s

Only the third is a voodu problem, and `drain { grace }` is the whole fix.

## `drain {}`

On `deployment` and `statefulset`.

```hcl
deployment "prod" "worker" {
  image = "ghcr.io/acme/worker:2.1"

  drain {
    grace   = "120s"   # SIGTERM → SIGKILL gap. No plugin needed.
    timeout = "30m"    # wait for a plugin to report the replica went quiet.
  }
}
```

| field | needs a plugin? | default |
| --- | --- | --- |
| `grace` | no | docker's own (10s) |
| `timeout` | yes — inert without one | 2m |

Both are `time.ParseDuration` strings, and **validated at parse** — unlike
other durations in voodu, a bad value fails the apply:

```
deployment.drain.timeout: "30min" is not a duration (want e.g. "30s", "5m", "1h30m")
```

That break with convention is deliberate: a probe interval falling back to a
default is a nuisance, while a drain timeout doing the same cuts exactly the
work the block was written to protect.

The wait **never wedges a roll**. A socket whose peer vanished without a FIN
never closes; when the budget runs out the removal proceeds and the forced cut
is logged.

## Plugin blocks

A block voodu does not recognise inside a workload belongs to the plugin of
that name:

```hcl
deployment "prod" "esl" {
  image    = "ghcr.io/acme/esl:1.2"
  replicas = 3
  ports    = ["8084"]        # ephemeral host port — replicas coexist

  drain  { timeout = "30m" }
  traffik { port = 8084 }     # the CONTAINER port traffik forwards to
}
```

Voodu never reads inside the block. It knows the name, the labels and the body
as opaque JSON — enough to find the owning plugin, nothing about what it does.
That is what keeps a plugin block from becoming a contract every plugin of its
family must satisfy.

**Errors land at apply, not in a container:**

```
deployment/prod/esl: block "traffik" belongs to a plugin named "traffik", which
is not installed — run `vd plugins:install <source>` or remove the block
```

A block may repeat, with labels naming each one:

```hcl
traffik "sip"  { port = 5060 }
traffik "http" { port = 8084 }
```

## What the rollout does

```
  bring the replacement up          ← deployment only
  wait for it to report ready
  stop sending work to the old one
  wait for its work to finish       ← drain.timeout
  SIGTERM, then SIGKILL             ← drain.grace
  remove
```

**Deployments surge** when nothing pins a host port. `ports = ["8080"]`
normalises to `127.0.0.1::8080` — docker picks the host side — so replicas
coexist. A pinned host port (`"3000:8080"`) means one container holds it, so
the replacement waits.

**Statefulsets never surge, by design.** Each ordinal owns a named volume that
survives container removal; two containers mounting one volume is corruption,
not less downtime. They still drain and still honour `grace`.

## voodu-traffik

The L4 TCP load balancer plugin ([thadeu/voodu-traffik](https://github.com/thadeu/voodu-traffik)),
for raw TCP on ports Caddy does not reach — ESL, database proxies, anything
where a connection is the unit of work.

```sh
vd plugins:install thadeu/voodu-traffik
vd traffik:status
```

`port` is the only required field. `bind` defaults to `127.0.0.1:<port>`
(loopback, following voodu's rule for published ports); write
`bind = "0.0.0.0"` to go public.

**A pinned host port is refused at apply** — one container can hold it, so
there is nothing to balance and the rollout cannot surge. Drop the host side
of `ports` and let traffik be the way in.
