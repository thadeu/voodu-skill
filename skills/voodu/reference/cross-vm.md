# Cross-VM — apps on one host, databases on another

Several voodu hosts joined by WireGuard behave as one network: a container on
any host reaches a container on any other **by the same `.voodu` name it has
locally, on the process's own port, with zero lines in the manifest**.

Full docs: https://voodu.clowk.in/docs/getting-started/cross-vm

## The model in one table

| Thing | Value | Where it comes from |
|---|---|---|
| host's tunnel address (`wg0`) | `10.254.X.Y` | last two numbers of the host's outbound IP (`152.53.91.221` → `10.254.91.221`) |
| host's container subnet (`voodu0`) | `10.X.Y.0/24` | derived from the tunnel address |
| statefulset pod | fixed IP, `.2`–`.127` | reserved by the controller, kept until the statefulset is deleted |
| deployment replica | ephemeral IP, `.128`–`.254` | docker; use the name, never the IP |
| name | `pg-0.contagorda.voodu`, `api.clowk.voodu` | the same aliases docker registers locally |

Nothing to configure per host: the installer derives everything; `--wg-address`
overrides only for a collision or an outbound IP whose third number is 254.

## How a name resolves across hosts

Every container is created with two resolvers: its own host's controller
(mesh DNS on the `voodu0` gateway) first, then the host's resolvers. Docker
answers local names itself; an unknown `.voodu` name reaches the controller,
which asks the wired peers over `wg0` — the host that owns the container
answers. Internet names go to the host's resolvers. Nothing is copied between
hosts, so nothing is stale; TTL 5s.

- Controller restarting (upgrade): internet names keep resolving; only remote
  `.voodu` names wait a few seconds.
- The same name on two hosts answers with both IPs (and logs it). Keep one
  scope per environment so staging and prod never share a name.
- Names without the suffix (`pg.contagorda`) are local-only.

## Ports: the rule

`ports` publishes on the **host**. A name reaches the **container**. They are
independent — and across hosts `ports` plays no part.

| Path | Who | Port |
|---|---|---|
| `127.0.0.1:<host port>` (`ports = [...]`) | this host only | one per host, cannot repeat, changes on recreate when left empty |
| `pg-0.clowk.voodu:5432` | apps on any host | the process's own — repeats freely |

Three databases, no `ports`, all on 5432:

```hcl
postgres "contagorda" "pg" { version = "16" }
postgres "clowk"      "pg" { version = "16" }
postgres "hep3"       "pg" { version = "16" }
```

```
postgres://…@pg-0.contagorda.voodu:5432/app
postgres://…@pg-0.clowk.voodu:5432/app
postgres://…@pg-0.hep3.voodu:5432/app
```

The `postgres` / `redis` plugins already emit these URLs — they work unchanged
from another host.

Avoid the old cross-host shapes: a fixed host port (`5433:5432`) or an empty
host port on a tunnel IP (`10.8.0.1::5432`). `vd apply` warns on the second
("leaves the host port empty on a non-loopback address").

## Reaching a container from the host itself

The host sees `voodu0` directly: `psql -h 10.91.221.2` needs no `ports`. For
names on the host, point systemd-resolved at the mesh DNS for the bridge only:

```sh
BR=br-$(docker network inspect voodu0 -f '{{.Id}}' | cut -c1-12)
sudo resolvectl dns "$BR" 10.91.221.1
sudo resolvectl domain "$BR" '~voodu'
```

## Ingress for a service on another host

The host running Caddy may front an app on another host: name it in `service`
and set `port` explicitly (its manifest is not on this host to read it from).
Caddy dials the name; a deploy on the other host needs nothing here.

```hcl
ingress "clowk" "api" {
  host    = "api.example.com"
  service = "api"
  port    = 8080
}
```

Re-run `vd plugins:install thadeu/voodu-caddy` once on a host migrated to a
routed `voodu0` (Caddy is started with the mesh resolvers by the install).

## Setup checklist

1. Install voodu on each host (WireGuard + routed `voodu0` come with it).
2. Open UDP 51820 on each host's firewall; with ufw also allow forwarding from
   `wg0` to the `voodu0` bridge and port 53 on `wg0` and the `voodu0` gateway.
3. Wire the hosts: `vd wire show` / `vd wire add` both ways — see [wire.md](wire.md).
4. Apply manifests as usual. URLs use names.

## Migrating a host that predates this

An existing `wg0` in another range (e.g. `10.8.0.x`) or a `voodu0` without a
subnet stays local: the installer never touches either. Migration is manual
and recreates every container on `voodu0` (volumes kept): move `wg0` to
`10.254.X.Y/16` (drop hand-written `[Peer]` blocks, add the voodu `PostUp`),
recreate `voodu0` routed, restart the controller, re-run the caddy plugin
install, re-apply manifests, then `vd wire`. Step-by-step in the docs link
above.

## Limitations

- Docker 28+ (routed access to unpublished ports).
- A container whose first network is not `voodu0` is not reachable across
  hosts and gets no fixed IP.
- Every container port is reachable from the other tunnel hosts; a host
  firewall rule accepting the subnet only from `wg0` closes the provider-side
  exposure.
