# Star Conflict — Unofficial Server in Docker

**Unofficial Server.** A standalone Star Conflict server in Docker: the
game's server-side applications under Wine plus native MongoDB/Redis next
to them. Connect — and play without the official servers.

> [!IMPORTANT]
> The project is not affiliated with Gaijin. On October 9, 2026 Gaijin shut
> down Star Conflict; the game lives on only through third-party unofficial
> servers. Briefly, from Gaijin's notice:
>
> - you may use the server files, modify the game, and connect
>   to unofficial servers;
> - **monetization is forbidden**; a public server must be labelled
>   **"Unofficial Server"**;
> - do not enter your Gaijin account credentials on unofficial servers —
>   use any made-up login (the account is created automatically).
>
> Full text — at [star-conflict.com](https://star-conflict.com/ru/).
> The repo contains **no game files** — only scripts and configs (license
> below). Everyone takes the game files from their own Steam copy.

## Status

Verified manually:

| What | Status |
|---|---|
| All 17 services start, Hub applies `cloud.xml` | ✅ |
| Registration/authorization, hangar, Mongo DB structure | ✅ |
| Leaderboards (Redis) | ✅ services connect |
| Client connection, battle entry, factions | ✅ |
| Full battle via LAN-IP node | ✅ (guard patch `patch-security-check.py`) |
| Full battle via white IP + DNAT (separate VPS, separate game host) | ✅ verified in prod 10.10.2026 |

If something is off — see [Diagnostics](#diagnostics) and open an issue
with a log excerpt.

## Requirements

- Docker 24+ with compose plugin, ~15 GB disk (image + databases), 4+ GB RAM;
- a Steam copy of the game of **the same build** as the clients (the
  `star conflict` folder: Linux — `~/.steam/steam/steamapps/common/`,
  macOS — `~/Library/Application Support/Steam/steamapps/common/`);
- Linux x86_64 is the primary option (Wine without emulation, 2–3 min startup);
  Mac ARM is experimental (emulation, ~5 min startup).

## Quick Start (local)

```bash
git clone <repo> starconflict && cd starconflict
./scripts/sync-game.sh "<path to the star conflict folder in Steam>"
cp .env.example .env
docker compose build
docker compose up -d
docker compose logs -f sc-server   # wait for "mongo up" / "redis up" and Hub start
```

Readiness check (expect ~17):

```bash
L=/opt/wineprefix/drive_c/users/root/AppData/Local/Targem/StarConflict/cloud/Hub/logs
docker exec starconflict-server sh -c "grep -c 'registered itself' $L/hub_*.log"
```

Client (the Windows build from the same Steam): on the login screen pick
**localhost** and enter any login/password. No account exists yet —
one is created automatically.

## Dedicated Server (Linux)

Two options — pick by where the client-reachable address lives:

**A. White IP on the machine itself** (the game runs there too):

```bash
# .env on the server:
SERVER_HOST=<white IP>
PATCH_SECURITY=1
# launch:
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

`docker-compose.prod.yml` moves `sc-server` into the host network of the host
(which also drops the port-range publishing) and points the databases at
`127.0.0.1`. The Hub sees its own IP on the interface itself,
`FAKE_IF_MODE=none` (don't touch anything).

**B. White IP on another machine (VPS) + DNAT** — verified in prod 10.10.2026:

```bash
# .env on the game machine:
SERVER_HOST=<white VPS IP>
PATCH_SECURITY=1
FAKE_IF_MODE=eth0
FAKE_HOSTS=1
# launch (plain bridge, WITHOUT the prod override):
docker compose up -d --build
```

Here the game machine doesn't own the white IP, so the entrypoint puts it
as a secondary `/32` on the default-route interface **inside** the container
netns (`eth0` mode) and writes the hostname first into the container's
`/etc/hosts` (dedics' `-hub` depends on that resolve). `dummy` mode is wrong
under Linux: the Hub doesn't see `NOARP` interfaces (`there is no my node
in xml`) — that's exactly what `eth0` is for. Host and VPN are untouched.

On the VPS (iptables): DNAT **TCP+UDP** `3800–3830`, `3850`, `35000–35099`,
`9000–9010` to the game machine + MASQUERADE/SNAT for the return path
(otherwise the dedi's replies go to the client straight from the game
machine's IP instead of the white one, and the client drops them). The client
connects via the **server** entry: `white-IP:3850`.

Game-machine firewall: allow the same ranges (TCP+UDP).
Do not expose `27017`, `6379`, `2222`. The client must be the same build
as the files in `game/`.

## Playing over the Internet/VPN (server behind NAT, separate reverse proxy)

The dedi used to crash when the node address wasn't a real local address —
i.e. when we fooled it with an address not actually present on the machine
(a dummy interface / hosts entry). With a genuine address (loopback or the
machine's own IP) it starts fine. In the spoofed case, the global crypto
object inside `RakNet::InitializeSecurity` stayed zeroed and the first
indirect call through it killed the process. Fixed by the guard in
`scripts/patch-security-check.py` (v2.4, applied from `entrypoint.sh`
when `PATCH_SECURITY=1`): a null pointer is substituted with the worker
of the branch a real battle uses (values observed by reading the memory
of a live loopback battle), the stdcall stack is cleaned, and execution
resumes past the patched spot.
Verified 10.10.2026: a full battle via `server <LAN-IP>:3850` with
`SERVER_HOST=<LAN-IP>` and via white IP with DNAT with
`SERVER_HOST=<white IP>` — `m_numSession`, `started at port 35000`,
`starting level`, the battle plays to the end, no dumps. In loopback mode
the guard never fires at all (1:1 behavior).

Fallback path without binary patches (forwarder on the player's side):

- on the server `SERVER_HOST=127.0.0.1`, plain bridge launch;
- on the VPS/proxy — DNAT the ranges from the section above to the game
  host's VPN-IP (TCP+UDP) + SNAT/MASQUERADE for the return path;
- the player enters the VPS white IP on the login screen (Hub is reachable
  directly), and for battle/chat raises a local forwarder (addresses
  `127.0.0.1` looped to the VPS):

```bash
python3 scripts/player-forward.py --target <white-VPS-IP>
```

(`--tcp`/`--udp` — ranges, sensible defaults; a root-only Linux alternative
without the script — DNAT of outgoing loopback traffic:

```bash
iptables -t nat -A OUTPUT -d 127.0.0.1 -p udp -m multiport \
    --dports 3815,3800:3830,3850,9000:9010,35000:35099 \
    -j DNAT --to-destination <white-VPS-IP>
```

and the same for `-p tcp`.) Ports >1024, no admin rights needed. Verified:
queue, matchmaking and a full battle work through such a chain.

## Configuration

### `.env`

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_HOST` | `127.0.0.1` | Address the server gives to the client (Hub, battles). For other PCs — LAN/white IP |
| `SERVER_PORT` | `3850` | Hub port |
| `SSH_PASSWD` | `hub1234` | Hub SSH console password (port 2222, localhost only). Short and simple — 2015-era engine |
| `PATCH_SECURITY` | `0` | `1` — null-call guard in `DedicatedServer.exe`. Required when the node ≠ `127.0.0.1` |
| `FAKE_IF_MODE` | `dummy` | Where to put `SERVER_HOST` inside the container netns: `dummy` (Mac/tests), `eth0` (Linux prod, see above), `none` (IP already local — option A) |
| `FAKE_HOSTS` | `1` | `1` — write `SERVER_HOST` first for the hostname in the container's `/etc/hosts` (dedics' `-hub` depends on that resolve) |

### Ports

| Ports | Who | Why |
|---|---|---|
| `3850` TCP/UDP | Hub | Client login, node management |
| `3800–3830` TCP/UDP | LoadBalancer `3801`, Shard `3802`, Chat `3815`, other services | Internal + client connects |
| `35000–35099` TCP/UDP | DedicatedServer (`net_gamePort=35000`, then `net_autoGamePort` takes free ones) | **Battles. Without this range — "network error" on battle entry** |
| `9000–9010` | Other services (a listener seen on `9001`) | Spare |
| `2222` (localhost only) | Hub SSH console | Server commands |
| `27017`, `6379` (localhost only) | MongoDB, Redis | Databases; don't expose |

### Files and scripts

| Path | What |
|---|---|
| `Dockerfile` | Debian + Wine (no game files — builds in seconds) |
| `entrypoint.sh` | Checks `./game`, runtime-patches `.exe`, patches `cloud.xml`, generates `common_local.cfg` / `hub_local.cfg`, waits for databases, starts Hub |
| `docker-compose.yml` / `docker-compose.prod.yml` | Databases + server / override for a Linux host (host network) |
| `scripts/sync-game.sh` | Copies `cloud/ + data/ (~11 GB) + sys_data/` from Steam into `./game/` |
| `scripts/patch-addr-assert.py` | One-byte patch of engine `.exe`s (details below), idempotent |
| `scripts/patch-security-check.py` | Null-call guard in `DedicatedServer.exe` for node ≠ `127.0.0.1` (`PATCH_SECURITY=1`), idempotent |
| `scripts/player-forward.py` | `127.0.0.1` → VPS forwarder for the no-patch fallback VPN scheme |
| `scripts/prepare-shared.sh` | Equivalent of the developers' `prepare_shared.bat` |
| `scripts/hub-console.sh` | Hub SSH console login (see status below) |
| `./game/` | Copy of the game files: mounted into the container, in neither git nor the image |

## Matchmaker and bot setup

Everything is in `game/cloud/data/default_platform_config.lua` (the file is
visible to the container right away — edit locally, apply with
`docker compose restart sc-server`, no rebuild needed). Details — in
`docs/matchmaking.md` inside the game folder.
The server is almost always in low-online mode (`queuesConfigLo`,
`mm_lowOnlineLo = 250`), edit the Lo queues specifically.

- "One against all" (Bug in the anthill): `special = { one_against_all = 1,
  botsCount = 7 }` — 1 player vs 7 bots, starts solo.
- More/fewer bots: `botsCount` in the queue's `special` (0..31, takes priority
  over global `cvars.mm_botsCount = 6`). This repo's arcade queues already
  set `botsCount = 8`.
- Solo start in another mode: `minPlayers = 1` + `botsCount = N` in `special`.

## Regenerating server xml

Per the developers' instructions: when lua **data** changes (ships, shop,
quests — not configs!), run `pc\cloud\prepare_shared.bat` with Mongo up.
Here: `./scripts/prepare-shared.sh` (the same inside the container,
changes are written straight into the mounted `./game/`). On stock files
everything is already in sync.

## Server console — experimental

The Hub has a console (`help`, `status`, `enterMaintenanceMode <min>`,
`leaveMaintenanceMode`, `quit`, ...) and two ways to reach it:

- `docker attach` — **doesn't work**: the Hub writes/reads through the Windows console
  (conhost), not Unix stdin/stdout;
- SSH to `127.0.0.1:2222` (`scripts/hub-console.sh`) — the server comes up
  (banner `SSH-2.0-targem.ssh`), but password auth doesn't go through yet.
  Status: under investigation, PRs welcome.

Stop/restart via compose works as usual.

## Useful

- Service logs:
  `docker exec starconflict-server ls /opt/wineprefix/drive_c/users/root/AppData/Local/Targem/StarConflict/cloud/Hub/logs/`
- Manual DB edits (gold, premiums etc. — as in the developers' instructions):
  Mongo on `127.0.0.1:27017`, database `cosmosim_root`, collection `accounts`.
- Progress reset: `docker compose down -v` (equivalent of deleting
  `%LOCALAPPDATA%/Targem/StarConflict/cloud/mongodb/data`).
- `cloud.xml` is patched on every start from `SERVER_HOST/SERVER_PORT` —
  don't edit by hand.

## Diagnostics

| Symptom | Cause and fix |
|---|---|
| `there is no my node in xml`, Hub keeps restarting | Hub doesn't see its IP. Option A — only via `docker-compose.prod.yml` (host network). Option B — `FAKE_IF_MODE=eth0` (not `dummy`: the Hub doesn't see `NOARP` interfaces under Linux) + `FAKE_HOSTS=1`. If the entrypoint logs `point ... first` but Docker wipes the line from `/etc/hosts` right away — just restart the container |
| Battle entry — "network error", dedi started and died | Battle port range not forwarded. Locally: `35000–35099` in compose; option A: host network handles it; option B: TCP+UDP DNAT + MASQUERADE on the VPS |
| Dedi crashes at battle start, fresh `.dmp` in `Hub/dediserver_exceptions/` | Guard not applied: check `PATCH_SECURITY=1` and the `DedicatedServer.exe patched`/`already-patched` line in container logs |
| `Aggregate: !ok`, `FailedToParse: 'cursor' option is required` | Database newer than 3.4. You need `mongo:2.6` (same version as shipped with the game) |
| `InvalidNamespace: system.indexes` | Same cause — only `mongo:2.6` |
| `int 3` / `Unhandled exception 0x80000003` on `.exe` start | Broken runtime patch? Check the `patch addr-assert` output in container logs |
| Client doesn't connect at all | 1) Hub up? (registration counter ~17) 2) firewall 3) client set to **server**, not localhost 4) client build = `game/` build |

## How it works

- The server `.exe`s are 32-bit Windows binaries. Wine runs them in the
  container; the Hub itself raises the other 16 services per `cloud/data/cloud.xml`.
- The stock `mongod.exe` 2.6 crashes under Wine (`FileAllocator`, assertion
  `file_allocator.cpp:92` — verified on `Z:\`, `C:\`, with `--noprealloc`),
  hence native `mongo:2.6` and `redis:7-alpine` containers next to it.
  The mongo version is critical: the 2015-era driver sends `aggregate` without
  `cursor` (on 3.6+ — `FailedToParse`, dead queue/clans/factions; proven
  with a sniffer) and creates indexes by writing to `system.indexes` (on 4.2+ —
  `InvalidNamespace`).
- `patch-addr-assert.py`: the engine's Kernel_Memory reserves a `VirtualAlloc`
  pool at an unaligned address and demands exactly the requested address back,
  else it hits `int3`. Windows returns as-is, Wine rounds to 64K — without the
  patch every `.exe` crashes. The patch swaps `int3` for `nop`, and the engine
  uses the actually allocated base. Found by disassembling,
  confirmed with registers in winedbg.
- `patch-security-check.py`: guard around the null call in the crypto
  initializer (the global crypto object stays zeroed when the node address
  is spoofed — its factory never runs). Two call sites are rerouted through
  code caves: a null pointer is substituted with the worker of the branch a
  real battle uses (values observed by reading a live loopback battle's
  memory), the stdcall stack is cleaned, and execution resumes past the
  patched bytes. Patterns are strict (single match), application is
  idempotent.
- The entrypoint prepares the container network: `SERVER_HOST` is put as a
  secondary `/32` on dummy/`eth0` **inside** the container netns (host and VPN
  untouched) and written first for the hostname into `/etc/hosts` — dedics'
  `-hub` depends on that resolve (node address, else fallback `127.0.0.1`).

## Limitations and rules

- Non-commercial use only; label a public server **"Unofficial Server"**.
- The repo has no game files — everyone uses their own Steam copy.
- Use at your own risk (see Gaijin's notice of 09.10.2026).

## License

Repo scripts and configs — MIT (see `LICENSE`). Star Conflict game files,
name and assets belong to Gaijin/StarGem and are not covered by MIT.
