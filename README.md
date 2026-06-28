# icarus.local

On-demand self-hosted service stack for a personal MacBook Pro M1.  
Every service is dormant by default — start what you need, stop it when done.

See [ICARUS_LOCAL_PLAN.md](ICARUS_LOCAL_PLAN.md) for the full concept, architecture, and operational playbook.

---

## Prerequisites

- [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/) — set memory to at least 8 GB in Settings → Resources
- [Ollama](https://ollama.com/) on the host (for Open WebUI and OpenHands): `brew install ollama`

---

## First-time setup

```bash
git clone git@github.com:kasunben/icarus.local.git
cd icarus.local
make init              # creates .env from .env.example
make keygen-all        # prints all generated secrets — paste into .env
```

Fill in `.env`. The `keygen-all` output covers most secrets.  
You'll also need to set `PIHOLE_WEBPASSWORD`, `ANTHROPIC_API_KEY`, and `CODING_WORKSPACE`.

---

## Starting services

```bash
make up SERVICE=n8n          # starts n8n (pulls Postgres + Redis automatically)
make up SERVICE=nextcloud    # starts Nextcloud (pulls MariaDB + Redis automatically)
make up SERVICE=searxng
make up SERVICE=garage       # see Garage bootstrap below
make up SERVICE=open-webui
make up SERVICE=openhands
make up SERVICE=bentopdf
make up SERVICE=changedetection
make up SERVICE=glances
make up SERVICE=pihole
make build SERVICE=coding-sandbox && make up SERVICE=coding-sandbox
```

```bash
make ps                      # what's running
make open SERVICE=<name>     # print the localhost URL
make down SERVICE=<name>     # stop (volumes preserved)
make shell SERVICE=<name>    # bash shell inside container
```

---

## Garage bootstrap (one-time)

Garage's S3 endpoint is up but not initialised after first start.

```bash
make up SERVICE=garage
make garage-init             # bootstraps layout, creates key + bucket, prints credentials
```

Copy `GARAGE_ACCESS_KEY` and `GARAGE_SECRET_KEY` from the output into `.env`.

---

## Backup

```bash
make backup-all              # all volumes + Postgres + MariaDB dumps → backups/
```

**Warning:** backups go to the same disk as your data. Set up an offsite copy before relying on them.

---

## Port reference

| Service | URL |
|---|---|
| n8n | http://localhost:5678 |
| Nextcloud | http://localhost:8091 |
| SearXNG | http://localhost:8888 |
| Garage S3 | http://localhost:3900 |
| Open WebUI | http://localhost:3000 |
| OpenHands | http://localhost:3100 |
| BentoPDF | http://localhost:8090 |
| changedetection | http://localhost:5000 |
| Glances | http://localhost:61208 |
| Pi-hole | http://localhost:8053/admin |
