# icarus.local — Concept & Execution Plan

**Project name:** icarus.local  
**Owner:** Kasun  
**Status:** In progress  
**Last updated:** 2026-06-22 (v5 — scope reduced to personal computer only; presets removed; Caddy removed; stack simplified)

---

## 1. Concept

### What it is

icarus.local is a self-hosted, on-demand service stack for a personal computer, starting on a MacBook Pro M1 (2020). It replaces cloud dependencies — Google Drive, Google Search, ChatGPT, S3 storage — with services you own and control, running on your own hardware.

Every service is dormant by default. You start what you need, when you need it, and shut it down when you're done. Nothing runs in the background unless you explicitly asked for it.

### Core principles

**On-demand, not always-on.** One command starts a service. One command stops it. No service runs unless explicitly requested.

**Config as source of truth.** The Git repository is the infrastructure. Any machine reproduces the full stack from `git clone` + `make init`. Secrets live only in `.env` — never in the repo.

**Portable by design.** The stack is scoped to a personal computer today, but the design doesn't lock you in. If you ever want to run a service on a different machine, the procedure is: backup volumes, clone repo, make init, restore volumes. Nothing in the repo is machine-specific.

**Vendor independence.** No cloud providers, no SaaS APIs, no managed services. All data stays on hardware you control. Services that phone home are configured not to.

**Shared infrastructure, isolated services.** Postgres and Redis are shared across services that need them. Each service gets its own database — no cross-service coupling. The AI cluster (Open WebUI + OpenHands) runs on a separate network with no access to the main stack's data.

**Backup by design.** Every service's data lives in a named Docker volume. Volume archives plus SQL dumps. Backup and restore are first-class Makefile targets.

**Localhost-only.** All ports bind to `127.0.0.1`. Services are only reachable from this machine. Cross-device access is a separate decision made later if needed, not a built-in assumption.

---

## 2. Architecture

### Infrastructure layer

| Component | Role | Image |
|---|---|---|
| **Postgres 16** | Shared relational DB | `postgres:16-alpine` |
| **Redis 7** | Shared cache / queue / file-lock | `redis:7-alpine` |
| **MariaDB 11 LTS** | Nextcloud-dedicated DB | `mariadb:11-lts` |
| **`icarus-net`** | Main stack network | bridge |
| **`ai-net`** | Isolated AI cluster network | bridge |

Postgres and Redis start automatically as dependencies when a service that needs them is brought up. You never start them manually.

### Services

| Service | Profile | Port(s) | Purpose | Storage |
|---|---|---|---|---|
| **Postgres** | `postgres` | 5432 | Shared relational DB | Named volume |
| **Redis** | `redis` | 6379 | Shared cache / queue | Named volume |
| **Garage** | `garage` | 3900 / 3903 | S3-compatible object storage | Named volumes |
| **SearXNG** | `searxng` | 8888 | Private meta-search engine | Config in git + cache volume |
| **Nextcloud** | `nextcloud` | 8091 | Self-hosted cloud storage | MariaDB + Redis + named volumes |
| **n8n** | `n8n` | 5678 | Workflow automation | Postgres + Redis + named volume |
| **Open WebUI** | `open-webui` | 3000 | Chat UI for local + cloud LLMs | Named volume |
| **OpenHands** | `openhands` | 3100 | Autonomous AI agent sandbox | Named volume |
| **BentoPDF** | `bentopdf` | 8090 | Client-side PDF toolkit | None (stateless) |
| **changedetection** | `changedetection` | 5000 | Webpage change monitoring | Named volume |
| **Glances** | `glances` | 61208 | System resource monitor | None |
| **Pi-hole** | `pihole` | 53 / 8053 | System-wide DNS ad-blocker | Named volume |
| **Coding Sandbox** | `coding-sandbox` | — | Claude Code + Open Code dev env | Named volumes + host mount |

### Dependency graph

```
make up SERVICE=n8n
  └── postgres (healthcheck) + redis (healthcheck) + n8n

make up SERVICE=nextcloud
  └── nextcloud-db/MariaDB (healthcheck) + redis (healthcheck) + nextcloud

make up SERVICE=garage
  └── garage + garage-init (one-shot bootstrap sidecar, exits after first run)

make up SERVICE=<anything else>
  └── only that service
```

### Network topology

```
icarus-net (main stack)
  └── postgres, redis, n8n, nextcloud, nextcloud-db,
      searxng, garage, changedetection, glances,
      bentopdf, pihole, coding-sandbox

ai-net (isolated — no access to icarus-net)
  └── open-webui, openhands
  └── explicitly allowed: → searxng (web search)
  └── explicitly allowed: → garage (file storage)
  └── no access to: postgres, redis, nextcloud, n8n
```

The AI cluster is isolated by network, not by firewall rule. OpenHands cannot resolve `postgres` or `nextcloud` by hostname because those names don't exist on `ai-net`. The two allowed connections are explicit bridge entries.

### Volume naming

All volumes prefixed `icarus-`. Format: `icarus-<service>-<type>`. Named explicitly so they survive compose project renames.

---

## 3. Repository structure

```
icarus.local/
├── docker-compose.yml              # Single source of truth for all services
├── .env.example                    # Committed — all vars documented, no values
├── .env                            # Gitignored — secrets for this machine
├── .gitignore
├── Makefile                        # All operational commands
├── README.md                       # Quick-start reference
│
├── backups/                        # Gitignored — local backup output
│   └── .gitkeep
│
├── scripts/
│   ├── backup-all.sh               # Full backup: DB dumps + volume archives
│   └── new-service.sh              # Scaffold a new service
│
└── services/
    ├── postgres/
    │   └── init/
    │       └── 01-create-databases.sql   # Runs once on first Postgres boot
    ├── searxng/
    │   └── config/
    │       ├── settings.yml        # Committed — instance config
    │       └── limiter.toml        # Committed — rate limiter config
    ├── garage/
    │   └── garage.toml             # Committed — no secrets in it
    └── coding-sandbox/
        └── Dockerfile              # Ubuntu 24.04 + Node 22 + Claude Code + Open Code
```

---

## 4. Key technical decisions

### Why a single `docker-compose.yml` with profiles

One file to read, one file to edit, one file to commit. Shared infrastructure (Postgres, Redis, networks, volumes) is declared once. Alternative approaches — separate compose files, a wrapper CLI — add coordination overhead without adding value for a single-machine personal stack.

The profile per service means any service can be started individually with `--profile <name>` or via the `make up SERVICE=<name>` shorthand. No service runs without explicit activation.

### Why the AI cluster is on a separate network

OpenHands is an autonomous agent that executes code it writes itself. Putting it on `icarus-net` would mean a manipulated agent could reach Postgres, n8n webhooks, or Nextcloud's internal API by hostname. On `ai-net`, none of those hostnames resolve. The isolation is architectural — there's nothing to misconfigure.

Open WebUI sits on `ai-net` too because it's the front door to the AI cluster. Its only connections outside `ai-net` are to Ollama on the host (via `host.docker.internal`) and optionally to SearXNG and Garage through explicit bridge entries.

### Why OpenHands and not something else for the agent sandbox

OpenHands is purpose-built for autonomous agent execution with isolation as a primary design goal. It spawns per-session Docker containers for code execution, has a published image, and is actively maintained. The key distinction from the coding sandbox: OpenCode (in the coding sandbox) is a terminal assistant you drive interactively; OpenHands is an agent you delegate tasks to and come back to. They don't overlap.

### Why the coding sandbox is separate from the agent sandbox

The coding sandbox has your GitHub credentials, SSH keys, and your actual code mounted at `/workspace`. An autonomous agent with access to those is a meaningful risk — not because agents are malicious, but because they can misunderstand scope and make irreversible changes. Two containers, two networks, two purposes. This is not optional.

### Why Garage instead of MinIO

MinIO's GitHub repository was archived April 2026. Garage is built by Deuxfleurs, a French non-profit funded by European NGI grants — no VC money, AGPL-3.0, actively maintained, designed for small self-hosted deployments. Single-node Docker works today and can expand to multi-node without data migration.

### Why Nextcloud gets its own MariaDB

Nextcloud's official setup requires MariaDB with specific binary log flags (`--transaction-isolation=READ-COMMITTED`, `--binlog-format=ROW`). Running it against shared Postgres creates upgrade coupling. Keeping it on a dedicated MariaDB container is cleaner and officially supported.

### Why BentoPDF and not Stirling-PDF

BentoPDF processes everything in the browser — no server state, no volume, nothing to back up. Stirling-PDF is over 1 GB, consumes hundreds of MB at idle, and has had documented issues with a tracking pixel and freemium drift. For a single-user stack the server-side model adds weight without adding value.

### Why Pi-hole on a personal MacBook

Pi-hole as a system-wide DNS sinkhole blocks ads and trackers for every app on the machine — not just the browser. This is meaningfully different from a browser extension. The Docker-on-macOS constraint means it can only filter traffic from the Mac itself (not other LAN devices), but that's still useful.

Port 53 may conflict with `mDNSResponder` on macOS. If Pi-hole fails to start, see Known Issues.

### Why Open WebUI doesn't bundle Ollama

Ollama belongs on the host, not inside Docker. It needs direct Metal GPU access on Apple Silicon, manages its own model storage, and has its own lifecycle. All AI services in this stack connect to host Ollama via `host.docker.internal:11434`.

### Why all ports bind to `127.0.0.1`

On a laptop that moves between networks, binding to `0.0.0.0` exposes services to every network you connect to — including untrusted ones. `127.0.0.1` means only this machine can reach them. If you want cross-device access later, a `docker-compose.override.yml` (gitignored) handles it per-network without touching the main compose file.

### Why SearXNG config is committed to git

`settings.yml` controls which engines are enabled, the instance name, and whether the JSON API is on — all things you'll tune over time. It's config, not state. The cache volume is not committed.

### Why the coding sandbox stays running idle

The container runs a `sleep` loop so `make shell SERVICE=coding-sandbox` gives an instant shell without startup cost. Your code lives on the host at `CODING_WORKSPACE`, mounted read-write. Nothing valuable is inside the container.

---

## 5. Execution plan

### Phase 0 — Repository setup

- [ ] Create GitHub repo `kasunben/icarus.local` (private)
- [ ] Add all files as initial commit
- [ ] Verify `.gitignore` covers `.env`, `backups/`, `docker-compose.override.yml`
- [ ] Push to `main`

```bash
git init
git remote add origin git@github.com:kasunben/icarus.local.git
git add .
git commit -m "feat: initial icarus.local stack"
git push -u origin main
```

**Done when:** repo on GitHub, all config committed, `.env` absent from repo.

---

### Phase 1 — Bootstrap on MacBook Pro M1 2020

**Prerequisite:** Docker Desktop for Mac installed and running. All images have ARM64 variants — no special flags needed.

- [ ] `git clone git@github.com:kasunben/icarus.local.git && cd icarus.local`
- [ ] `make init` — creates `.env` from `.env.example`, creates required directories
- [ ] Fill in `.env`:
  - Postgres, Redis, Nextcloud passwords: `openssl rand -hex 24`
  - n8n encryption key: `make keygen`
  - SearXNG + Garage + Open WebUI secret keys: `openssl rand -hex 32` (one each)
  - Garage RPC secret + admin token: `openssl rand -hex 32` (two separate values)
  - `CODING_WORKSPACE` → your code directory (e.g. `~/Developer`)
  - `ANTHROPIC_API_KEY` if using Claude Code
  - Pi-hole web password
- [ ] Smoke-test shared infrastructure:
  - [ ] `make up SERVICE=postgres` → `make db-shell DB=icarus` (should get psql prompt)
  - [ ] `make up SERVICE=redis` → `docker exec -it icarus-redis redis-cli -a $REDIS_PASSWORD ping` (should return PONG)
- [ ] Bring up services one at a time, verify each before the next:
  - [ ] `make up SERVICE=garage` → run Garage bootstrap (see below) → verify S3 endpoint responds
  - [ ] `make up SERVICE=searxng` → `http://localhost:8888` → run a test search
  - [ ] `make up SERVICE=n8n` → `http://localhost:5678` → complete setup wizard
  - [ ] `make up SERVICE=nextcloud` → `http://localhost:8091` → complete setup wizard
  - [ ] `make up SERVICE=open-webui` → `http://localhost:3000` → create admin account immediately
  - [ ] `make up SERVICE=openhands` → `http://localhost:3100` → configure LLM, run a test task
  - [ ] `make up SERVICE=bentopdf` → `http://localhost:8090` → merge two PDFs
  - [ ] `make up SERVICE=changedetection` → `http://localhost:5000`
  - [ ] `make up SERVICE=glances` → `http://localhost:61208`
  - [ ] `make up SERVICE=pihole` → `http://localhost:8053/admin` → set Mac DNS to `127.0.0.1`
  - [ ] `make build SERVICE=coding-sandbox` → `make up SERVICE=coding-sandbox` → `make shell SERVICE=coding-sandbox` → `claude --version`
- [ ] `make backup-all` → verify files appear in `backups/`
- [ ] Commit any config fixes discovered during smoke-test

**Garage first-run bootstrap** (one-time, after `make up SERVICE=garage`):
```bash
# Get node ID
docker exec icarus-garage /garage status

# Assign layout (replace <NODE_ID> with output from above)
docker exec icarus-garage /garage layout assign -z local -c 50G <NODE_ID>
docker exec icarus-garage /garage layout apply --version 1

# Create bucket and access key
docker exec icarus-garage /garage key create icarus-key
docker exec icarus-garage /garage bucket create icarus
docker exec icarus-garage /garage bucket allow icarus --read --write --key icarus-key

# Print credentials — copy into .env as GARAGE_ACCESS_KEY and GARAGE_SECRET_KEY
docker exec icarus-garage /garage key info icarus-key
```

**Done when:** all services start without errors, backup-all runs cleanly, Nextcloud and n8n wizards complete, Open WebUI admin account created.

---

### Phase 2 — Nextcloud post-install hardening

- [ ] Configure Redis as memory cache:
  ```bash
  make nextcloud-occ CMD="config:system:set memcache.locking --value='\\OC\\Memcache\\Redis'"
  make nextcloud-occ CMD="config:system:set memcache.local --value='\\OC\\Memcache\\APCu'"
  make nextcloud-occ CMD="config:system:set memcache.distributed --value='\\OC\\Memcache\\Redis'"
  make nextcloud-occ CMD="config:system:set redis --type=json --value='{\"host\":\"redis\",\"port\":6379,\"password\":\"<REDIS_PASSWORD>\"}'"
  ```
- [ ] Set phone region: `make nextcloud-occ CMD="config:system:set default_phone_region --value='DE'"`
- [ ] Check `http://localhost:8091/settings/admin/overview` — no warnings or errors
- [ ] Install apps via web UI as needed (Calendar, Contacts, Notes)

**Done when:** Admin Overview is clean.

---

### Phase 3 — AI cluster setup

- [ ] Install Ollama: `brew install ollama` → starts as a macOS service automatically
- [ ] Pull a starter model: `ollama pull qwen3:8b`
- [ ] Verify Ollama: `curl http://localhost:11434/api/tags`
- [ ] **Open WebUI:**
  - [ ] Settings → Connections → Ollama API at `http://host.docker.internal:11434` — verify models appear
  - [ ] Optional: add Anthropic API → base URL `https://api.anthropic.com/v1`, key from `.env`
  - [ ] Optional: Settings → Web Search → SearXNG at `http://icarus-searxng:8080/search?q=<query>&format=json`
  - [ ] Send a test message — confirm response
- [ ] **OpenHands:**
  - [ ] Configure LLM backend at `http://localhost:3100`
  - [ ] Run a test task against a throwaway repository
  - [ ] Confirm it does not have access to `~/Developer` or any credential files

**Done when:** Open WebUI returns a response; OpenHands completes a sandboxed task.

---

### Phase 4 — Coding sandbox validation

- [ ] `make shell SERVICE=coding-sandbox`
- [ ] `claude --version` and `opencode --version`
- [ ] `ls /workspace` — should show your `CODING_WORKSPACE` directory
- [ ] `cd /workspace/<a-project> && claude` — Claude Code reads project files
- [ ] `echo $ANTHROPIC_API_KEY` — key is present

**Done when:** Claude Code launches and reads workspace files.

---

### Phase 5 — Cross-device access (when needed, not before)

Deferred until Phase 1–4 are stable and you know which services you want on other devices.

**Option A — LAN rebind (home network only)**

Create `docker-compose.override.yml` (gitignored, not committed):
```yaml
services:
  nextcloud:
    ports:
      - "0.0.0.0:8091:80"
  n8n:
    ports:
      - "0.0.0.0:5678:5678"
  open-webui:
    ports:
      - "0.0.0.0:3000:8080"
```
Other devices point to the MacBook's LAN IP. No third-party dependency.

**Option B — Tailscale (any network)**

Tailscale creates an encrypted mesh between your devices. Requires a free Tailscale account. Services stay at `127.0.0.1`; a reverse proxy on the host (Caddy or similar) exposes selected services on the Tailscale interface if needed. Works from anywhere, not just home.

**Nextcloud trusted domains** (required for either option):
```bash
make nextcloud-occ CMD="config:system:set trusted_domains 1 --value='<ip-or-hostname>'"
```

**Done when:** at least one service accessible from a second device.

---

### Phase 6 — Migration to a new machine

Same procedure for any destination — new MacBook, home server, anything.

- [ ] `make backup-all` on current machine
- [ ] On new machine: install Docker, clone repo, `make init`, fill in `.env` from password manager
- [ ] Transfer backups: `scp backups/*.tar.gz backups/*.sql.gz <new-machine>:~/icarus.local/backups/`
- [ ] On new machine:
  ```bash
  make up SERVICE=postgres
  make restore VOLUME=icarus-postgres-data FILE=backups/icarus-postgres-data_<ts>.tar.gz
  make db-restore DB=n8n FILE=backups/n8n_<ts>.sql.gz
  # repeat for each volume and DB
  make up SERVICE=n8n  # verify, then continue with other services
  ```
- [ ] Update Nextcloud trusted domains if hostname changed
- [ ] `make down-all` on old machine

**Done when:** all services running on new machine, data intact.

---

## 6. Operational playbook

### Daily commands

```bash
make up SERVICE=<name>         # start a service (pulls in dependencies automatically)
make down SERVICE=<name>       # stop a service (volumes preserved)
make restart SERVICE=<name>    # restart
make logs SERVICE=<name>       # follow logs (Ctrl-C to stop)
make shell SERVICE=<name>      # open shell inside container
make ps                        # show what's running
```

### Building locally-built images

```bash
make build SERVICE=coding-sandbox   # rebuild after Dockerfile changes
make restart SERVICE=coding-sandbox
```

### Database

```bash
make db-shell DB=<name>             # psql into Postgres
make db-dump DB=<name>              # dump to backups/
make db-restore DB=<name> FILE=<path>
make nextcloud-occ CMD="<occ cmd>"  # run occ inside Nextcloud
```

### Backup and restore

```bash
make backup-all                     # all volumes + all DB dumps (run this regularly)
make backup VOLUME=icarus-<name>    # single volume
make restore VOLUME=icarus-<name> FILE=<path>
./scripts/backup-all.sh             # same as backup-all, cron-safe
```

### Updating images

```bash
docker compose pull <service>
make restart SERVICE=<service>
```

**Nextcloud — one major version at a time, never skip:**
```bash
# 1. Update NEXTCLOUD_IMAGE in .env (e.g. nextcloud:30-apache → nextcloud:31-apache)
docker compose pull nextcloud
make restart SERVICE=nextcloud
make nextcloud-occ CMD="upgrade"
make nextcloud-occ CMD="maintenance:mode --off"
```

### Adding a new service

```bash
./scripts/new-service.sh <name>
# Follow the printed checklist
```

Checklist:
1. Paste the generated block into `docker-compose.yml`
2. Add volume to top-level `volumes:` block
3. Add port var and any new secrets to `.env.example`
4. Add `CREATE DATABASE` to `services/postgres/init/01-create-databases.sql` if needed
5. Add volume to `VOLUMES` in `scripts/backup-all.sh`
6. Add help text to Makefile
7. Commit

---

## 7. Port reference

| Port | Service | Notes |
|---|---|---|
| 53 | Pi-hole DNS | TCP + UDP; set Mac DNS to `127.0.0.1` |
| 3000 | Open WebUI | |
| 3100 | OpenHands | |
| 3900 | Garage S3 API | Use `forcePathStyle: true` in S3 clients |
| 3903 | Garage Admin API | Internal only |
| 5000 | changedetection.io | |
| 5432 | Postgres | Internal — use `make db-shell` |
| 5678 | n8n | |
| 6379 | Redis | Internal only |
| 8053 | Pi-hole web UI | |
| 8088 | SearXNG | JSON API: append `?format=json` |
| 8090 | BentoPDF | |
| 8091 | Nextcloud | |
| 61208 | Glances | |

All bound to `127.0.0.1`. To expose on LAN: `docker-compose.override.yml` (gitignored).

---

## 8. Secrets reference

| Variable | How to generate |
|---|---|
| `POSTGRES_PASSWORD` | `openssl rand -hex 24` |
| `REDIS_PASSWORD` | `openssl rand -hex 24` |
| `N8N_ENCRYPTION_KEY` | `make keygen` |
| `GARAGE_RPC_SECRET` | `openssl rand -hex 32` |
| `GARAGE_ADMIN_TOKEN` | `openssl rand -hex 32` |
| `GARAGE_ACCESS_KEY` | `garage key create` after first start |
| `GARAGE_SECRET_KEY` | `garage key create` after first start |
| `SEARXNG_SECRET_KEY` | `openssl rand -hex 32` |
| `NEXTCLOUD_DB_ROOT_PASSWORD` | `openssl rand -hex 24` |
| `NEXTCLOUD_DB_PASSWORD` | `openssl rand -hex 24` |
| `OPEN_WEBUI_SECRET_KEY` | `openssl rand -hex 32` |
| `PIHOLE_WEBPASSWORD` | Strong passphrase |
| `ANTHROPIC_API_KEY` | console.anthropic.com |

Store all values in Proton Pass at setup time. The `.env` file is the only runtime copy.

---

## 9. Change log

| Date | Change |
|---|---|
| 2026-06-22 | Initial stack: Postgres, Redis, n8n, MinIO, Stirling-PDF, changedetection, Glances |
| 2026-06-22 | Added SearXNG, BentoPDF, Nextcloud, coding-sandbox, OpenJarvis |
| 2026-06-22 | Plan written |
| 2026-06-22 | v2 — Primary host → MacBook M1; Stirling-PDF → BentoPDF; Open WebUI added |
| 2026-06-22 | v3 — Tailscale → Phase 5; MinIO → Garage; Pi-hole added |
| 2026-06-22 | v4 — Two-layer preset system (personal/home/vps); OpenJarvis → OpenHands; AI cluster on ai-net |
| 2026-06-22 | v5 — Scope reduced to personal computer only; presets removed; Caddy removed; stack and plan simplified |

---

## 10. Known issues

**Docker Desktop memory on MacBook.** Set memory to at least 8 GB in Docker Desktop → Settings → Resources before running multiple services simultaneously.

**Garage layout init before first write.** The S3 endpoint returns 503 until the layout bootstrap is applied. Run the bootstrap commands in Phase 1. The `garage-init` sidecar attempts this automatically but can fail if the server isn't ready — run manually if needed.

**Garage credentials are post-start.** Access key and secret are generated after first start with `garage key create`. Update `.env` with them before any other service connects to Garage.

**Pi-hole port 53 conflict on macOS.** `mDNSResponder` may already own port 53. Check: `lsof -i :53`. If so, set `PIHOLE_DNS_PORT=5353` in `.env` and point Mac DNS to `127.0.0.1` port 5353.

**Pi-hole is local-only on macOS.** Docker Desktop networking prevents LAN-wide DNS. Pi-hole filters only the MacBook's own traffic. This is still useful — it covers all apps, not just the browser.

**OpenHands mounts the Docker socket.** OpenHands needs `/var/run/docker.sock` to spawn per-session sandbox containers. This is its standard deployment model and expected. It means OpenHands has Docker access on the host — it does not have access to your volumes or credentials unless you explicitly mount them.

**Open WebUI first-user is admin.** The first account created becomes the permanent admin. Create it immediately after first start.

**Nextcloud version pinning.** `NEXTCLOUD_IMAGE` in `.env` is pinned to a specific major version. When upgrading, increment by one major version at a time. Never use `:latest`.

**SearXNG secret key.** If SearXNG complains about its secret key on first start, the env var interpolation may not be working. Fallback: hardcode the value directly in `settings.yml` and add that file to `.gitignore`.

**Backup is local-only.** `backup-all.sh` writes to `backups/` on the same disk as the data. Set up an offsite copy — rsync to an external drive, or to a Garage bucket — before treating backups as a real recovery path.
