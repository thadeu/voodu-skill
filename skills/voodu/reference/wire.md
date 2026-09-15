# `vd wire` — wire voodu hosts over WireGuard

`vd wire` manages the WireGuard peers of a host: the other voodu hosts whose
containers it can reach by name. Peers live in the controller, are applied to
`wg0` at once (`wg syncconf`, the tunnel never drops) and come back after a
reboot. `wg0.conf` is written once by the installer and never edited by hand.

Requires hosts installed with WireGuard (the default since cross-VM support;
`SKIP_WIREGUARD=1` opts out). See [cross-vm.md](cross-vm.md) for the whole
model — addresses, names, migration.

## Commands

```sh
vd wire show                                  # this host, as a ready-to-paste `add` line
vd wire add --key K --address 10.254.X.Y [--endpoint host:51820]
vd wire remove 10.254.X.Y
vd wire list                                  # peers + link health
```

Every verb targets the controller of the host it runs against, so `-r` works
from anywhere.

## Wiring two hosts (the whole procedure)

`show` on one, `add` on the other, then the reverse:

```sh
vd wire show -r vm-1
# → vd wire add --key <vm-1 key> --address 10.254.91.221 --endpoint 152.53.91.221:51820
vd wire add -r vm-2 --key <vm-1 key> --address 10.254.91.221 --endpoint 152.53.91.221:51820

vd wire show -r vm-2
# → vd wire add --key <vm-2 key> --address 10.254.167.105 --endpoint 152.53.167.105:51820
vd wire add -r vm-1 --key <vm-2 key> --address 10.254.167.105 --endpoint 152.53.167.105:51820
```

All three flags describe the **other** host:

| Flag | What | Example |
|---|---|---|
| `--key` | its WireGuard public key | `AbC…=` |
| `--address` | its tunnel address (`wg0`) | `10.254.167.105` |
| `--endpoint` | its public IP + WireGuard port | `152.53.167.105:51820` |

`--address` alone drives the routing: the peer's container subnet
(`10.167.105.0/24`) is derived from it. A host behind NAT is added without
`--endpoint`.

Open UDP 51820 on every host. Three hosts = three pairs = six `add`s, once.

## `vd wire list`

```
this host: 10.254.91.221  key LOCALKEY…

ADDRESS         ENDPOINT              HANDSHAKE    RX/TX        KEY
10.254.167.105  152.53.167.105:51820  12s ago      2.0KB/100B   PEERKEY2…
10.254.200.7    1.2.3.4:51820         never        0B/0B        PEERKEY3…
```

- `HANDSHAKE never` → the peer has not answered yet; almost always UDP 51820
  closed on one side, or a wrong `--endpoint`.
- `not applied` → stored but not on `wg0`; the next add/remove or controller
  start applies it.
- A dead peer stays listed until `vd wire remove`.

## Errors

| Message | Cause |
|---|---|
| `not in the voodu tunnel` | `--address` outside `10.254.0.0/16` |
| `that is this host` | `--address` is the local host's own |
| `public key already used by peer X` | same key under another address |
| `wg0 is not up` | WireGuard not running on that host |
