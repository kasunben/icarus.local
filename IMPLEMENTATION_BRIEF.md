# icarus.local — Implementation Brief

> This document is a work order for Claude Code.
> Read this first, then read `ICARUS_LOCAL_PLAN.md` for full context.
> Do not start writing code until you have read both documents.

---

## What this project is

A personal, on-demand Docker service stack for a MacBook Pro M1 (2020).
All services are dormant by default. Any service starts and stops individually.
Single `docker-compose.yml`, single machine, no preset system.

Full concept and architecture is in `ICARUS_LOCAL_PLAN.md`.

---

## Current state of the repo

The following files exist but are **outdated** — they reflect earlier design
decisions that have since changed. They are starting points, not finished work.

| File | Problem |
|---|---|
| `docker-compose.yml` | Contains MinIO, Stirling-PDF, OpenJarvis — all removed. Missing Garage, OpenHands, Open WebUI, Pi-hole. Missing `ai-net` network. Wrong volume list. |
| `Makefile` | References removed services. Missing `garage-init`, `up-all`, `down-all` updates. `shell` target uses `sh` — should use `bash`. `up-all` and `down-all` are not needed — remove them. |
| `.env.example` | Contains MinIO, Stirling, OpenJarvis vars. Missing Garage, OpenHands, Pi-hole, Open WebUI vars. |
| `scripts/backup-all.sh` | References old volumes (MinIO, Stirling). Needs updating to current volume list. |
| `services/coding-sandbox/Dockerfile` | Likely fine — verify it installs Node 22, Claude Code, Open Code, and Python tools. |
| `services/searxng/config/settings.yml` | Likely fine — verify JSON API output is enabled. |
| `services/searxng/config/limiter.toml` | Likely fine. |
| `services/postgres/init/01-create-databases.sql` | Verify it creates the `n8n` database. No other services need a Postgres DB. |

The following files **do not exist yet** and must be created:

- `services/garage/garage.toml`
- `README.md`

---

## Authoritative service list

This is the complete, current list of services. Implement exactly these —
nothing more, nothing less.

| Service | Container name | Profile | Network(s) |
|---|---|---|---|
| Postgres 16 | `icarus-postgres` | `postgres` | `icarus-net` |
| Redis 7 | `icarus-redis` | `redis` | `icarus-net` |
| Nextcloud MariaDB | `icarus-nextcloud-db` | `nextcloud` | `icarus-net` |
| n8n | `icarus-n8n` | `n8n` | `icarus-net` |
| Nextcloud | `icarus-nextcloud` | `nextcloud` | `icarus-net` |
| SearXNG | `icarus-searxng` | `searxng` | `icarus-net` |
| Garage | `icarus-garage` | `garage` | `icarus-net` |
| Open WebUI | `icarus-open-webui` | `open-webui` | `ai-net` |
| OpenHands | `icarus-openhands` | `openhands` | `ai-net` |
| BentoPDF | `icarus-bentopdf` | `bentopdf` | `icarus-net` |
| changedetection.io | `icarus-changedetection` | `changedetection` | `icarus-net` |
| Glances | `icarus-glances` | `glances` | `icarus-net` |
| Pi-hole | `icarus-pihole` | `pihole` | `icarus-net` |
| Coding Sandbox | `icarus-coding-sandbox` | `coding-sandbox` | `icarus-net` |

**Removed from old compose file — do not include:**
- MinIO
- Stirling-PDF
- OpenJarvis

---

## Hard constraints

Read these carefully. Do not deviate from them.

**Networks**
- Two networks: `icarus-net` (main stack) and `ai-net` (AI cluster).
- Open WebUI and OpenHands are on `ai-net` only.
- All other services are on `icarus-net` only.
- Open WebUI and OpenHands may reach SearXNG and Garage via explicit
  cross-network aliases — they must not have general access to `icarus-net`.
- The isolation is the point. An AI agent must not be able to resolve
  `postgres`, `redis`, or `nextcloud` by hostname.

**Ports**
- All ports bind to `127.0.0.1` only. No exceptions.
- Pi-hole DNS port 53 also binds to `127.0.0.1` on macOS
  (it cannot do LAN-wide DNS on macOS anyway — see plan for why).

**Profiles**
- Every service has exactly one profile matching its service name.
- Postgres has profiles `[postgres, n8n]` — pulled in automatically by n8n.
- Redis has profiles `[redis, n8n, nextcloud]` — pulled in automatically.
- Nextcloud-db has profile `[nextcloud]` — pulled in automatically.
- No other auto-dependency profiles. Everything else is single-profile.

**Restart policy**
- All services use `restart: unless-stopped`.
- Do not use `restart: always`.

**Ollama**
- Ollama runs on the host, not in Docker. Do not add it as a service.
- Open WebUI and OpenHands connect to it via `host.docker.internal:11434`.
- Add `extra_hosts: ["host.docker.internal:host-gateway"]` to both.

**OpenHands**
- Use the official published image: `ghcr.io/all-hands-ai/openhands:main`
- Do not write a custom Dockerfile for it.
- It requires Docker socket access to spawn per-session sandbox containers:
  mount `/var/run/docker.sock:/var/run/docker.sock`.
- This is expected and intentional — document it in a comment.

**Coding Sandbox**
- Built from `./services/coding-sandbox/Dockerfile`.
- No exposed port. Shell access only via `docker exec`.
- Runs idle: `command: ["bash", "-c", "while true; do sleep 3600; done"]`
- Mounts `${CODING_WORKSPACE:-~/Developer}` to `/workspace`.
- Persists Claude config in a named volume.

**Garage**
- Image: `dxflrs/garage:v1.0.1` (or latest stable v1.x — check Docker Hub).
- Requires a one-time layout bootstrap after first start.
- Provide a `make garage-init` target that runs the bootstrap commands.
- Config file at `./services/garage/garage.toml` — see Garage section below.
- Access key and secret are generated post-start, not pre-configured.

**Nextcloud**
- Uses dedicated MariaDB (`icarus-nextcloud-db`), not shared Postgres.
- MariaDB requires these flags:
  `--transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW`
- Pin image via `${NEXTCLOUD_IMAGE:-nextcloud:30-apache}` — never use `:latest`.
- Depends on both `nextcloud-db` (healthcheck) and `redis` (healthcheck).

**Secrets**
- All secrets are referenced as `${VAR_NAME}` in the compose file.
- Use `:?error message` for required secrets (fail fast if unset).
- Use `:-default` for optional vars with safe defaults.
- Never hardcode a secret value in any committed file.

**up-all / down-all**
- Remove these targets from the Makefile. With dormant-by-default design,
  "start everything" is not a valid use case and invites mistakes.

---

## What to build

Work in this order. Verify each step before moving to the next.

### Step 1 — docker-compose.yml

Rewrite it from scratch based on the authoritative service list above and
the constraints. Keep the existing structure and comment style.

Key things to get right:
- Two networks declared at the top: `icarus-net` and `ai-net`.
- Volume list matches exactly the services in the plan — no MinIO, no
  Stirling, no OpenJarvis volumes.
- SearXNG and Garage reachable from `ai-net` via network aliases so
  Open WebUI and OpenHands can use them without joining `icarus-net`.
- Garage has a `garage-init` container (profile `garage`, `restart: no`,
  `depends_on: garage`) that runs the layout bootstrap once and exits.

### Step 2 — services/garage/garage.toml

Minimal single-node Garage config. Key settings:
- `metadata_dir` and `data_dir` pointing to volume-mounted paths.
- `rpc_secret` read from environment: `${GARAGE_RPC_SECRET}`.
- Admin API token: `${GARAGE_ADMIN_TOKEN}`.
- S3 API on port 3900, admin API on port 3903.
- `replication_factor = 1` (single node).

### Step 3 — Makefile

Update to match current service list. Key changes:
- Remove `up-all`, `down-all`, all MinIO/Stirling/OpenJarvis references.
- Add `garage-init` target.
- Add `make keygen-all` that prints all generated secrets at once for
  first-time setup (useful when filling `.env` for the first time).
- `shell` target should use `bash` not `sh` (coding-sandbox uses bash).
- `backup-all` target should list current volumes explicitly.
- Add `make open SERVICE=<name>` that prints the localhost URL for a service
  (just an echo — no browser opening, keeps it scriptable).

### Step 4 — .env.example

Rewrite to match current service list exactly. Sections:
- General (`TZ`, `CODING_WORKSPACE`)
- Postgres
- Redis
- n8n
- Nextcloud (image pin, DB passwords, PHP limits, trusted domains)
- SearXNG
- Garage (RPC secret, admin token, access key placeholder, secret placeholder)
- Open WebUI
- OpenHands
- Pi-hole
- Anthropic API key

Every secret should have a comment showing how to generate it.
Access key and secret for Garage should be marked as post-start values.

### Step 5 — scripts/backup-all.sh

Update volume list to match current services. Remove MinIO, Stirling,
OpenJarvis. Add Garage, Open WebUI, OpenHands, Pi-hole volumes.
Add Nextcloud MariaDB dump alongside the Postgres dumps.

### Step 6 — services/coding-sandbox/Dockerfile

Verify or rewrite. Must install:
- Ubuntu 24.04 base (ARM64-compatible)
- Node.js 22 LTS (via NodeSource)
- `@anthropic-ai/claude-code` globally via npm
- `opencode-ai` globally via npm
- Python 3, pip, uv, ruff, black
- Git, curl, jq, ripgrep

Must create a non-root `dev` user (UID 1000).
Working directory: `/workspace`.

### Step 7 — README.md

Short quick-start reference. Cover:
1. Prerequisites (Docker Desktop, Ollama on host)
2. `git clone` + `make init` + fill `.env`
3. Garage bootstrap (the one special case)
4. `make up SERVICE=<name>` pattern
5. Link to `ICARUS_LOCAL_PLAN.md` for full context

Keep it under 80 lines. It is not a substitute for the plan document.

### Step 8 — scripts/new-service.sh

Update the checklist it prints to reflect current architecture:
- Mention adding to `icarus-net` or `ai-net` as appropriate
- Remove any references to preset system or COMPOSE_PROFILES

---

## Garage bootstrap detail

After `make up SERVICE=garage`, the S3 endpoint is running but not yet
initialised. The `garage-init` sidecar handles this automatically, but
`make garage-init` should also work as a manual fallback:

```bash
# Get node ID
docker exec icarus-garage /garage status

# Assign layout
docker exec icarus-garage /garage layout assign \
  --zone local --capacity 50G <NODE_ID>
docker exec icarus-garage /garage layout apply --version 1

# Create key and bucket
docker exec icarus-garage /garage key create icarus-key
docker exec icarus-garage /garage bucket create icarus
docker exec icarus-garage /garage bucket allow \
  icarus --read --write --key icarus-key

# Print credentials (copy into .env)
docker exec icarus-garage /garage key info icarus-key
```

The `make garage-init` Makefile target should print a prompt if the layout
is already applied rather than erroring.

---

## Common mistakes to avoid

- **Do not add Ollama as a Docker service.** It runs on the host.
- **Do not put Open WebUI or OpenHands on `icarus-net`.** They belong on
  `ai-net` only.
- **Do not use `restart: always`.** Use `restart: unless-stopped`.
- **Do not use `:latest` for Nextcloud.** Use the pinned image var.
- **Do not mount `~/Developer` or any credential path into OpenHands.**
  It gets the Docker socket only.
- **Do not generate random secret values** in compose or env files.
  Always reference `${VAR_NAME}`.
- **Do not add `up-all` or `down-all` back.** They were removed deliberately.
- **Do not expose any port on `0.0.0.0`.** All bindings are `127.0.0.1`.

---

## Definition of done

- [ ] `docker compose config` validates without errors
- [ ] `make up SERVICE=postgres` starts Postgres, healthcheck passes
- [ ] `make up SERVICE=n8n` starts n8n, Postgres and Redis come up as
      dependencies automatically
- [ ] `make up SERVICE=nextcloud` starts Nextcloud, MariaDB and Redis come
      up as dependencies automatically
- [ ] `make up SERVICE=garage` starts Garage, garage-init runs and exits
- [ ] `make up SERVICE=open-webui` starts Open WebUI on `ai-net`
- [ ] `make up SERVICE=openhands` starts OpenHands on `ai-net`
- [ ] `make up SERVICE=coding-sandbox` builds and starts the sandbox,
      `make shell SERVICE=coding-sandbox` opens a bash shell
- [ ] `make up SERVICE=pihole` starts Pi-hole
- [ ] `make garage-init` runs without error (or prints "already initialised")
- [ ] `make backup-all` runs without error and creates files in `backups/`
- [ ] `docker network inspect icarus-ai-net` shows only open-webui and
      openhands (verifying AI cluster isolation)
- [ ] No service has a port bound to `0.0.0.0`
- [ ] `.env.example` has an entry for every secret referenced in
      `docker-compose.yml`
