# Coding Sandbox — Usage Guide

The coding sandbox is an isolated Ubuntu 24.04 container pre-loaded with Claude Code CLI,
Open Code, Node.js 22, Python 3, and common dev tools. It runs as a non-root `dev` user
and mounts your local code directory at `/workspace`.

---

## What's inside

| Tool | Version |
|---|---|
| Claude Code | `@anthropic-ai/claude-code` (latest at build time) |
| Open Code | `opencode-ai` (latest at build time) |
| Node.js | 22 LTS |
| Python | 3.x + `uv`, `ruff`, `black` |
| Shell tools | `git`, `jq`, `ripgrep`, `curl` |

---

## First-time setup

**1. Build the image**

```bash
make build SERVICE=coding-sandbox
```

This step is required once, and again any time the Dockerfile changes (e.g. after a tool update).

**2. Start the container**

```bash
make up SERVICE=coding-sandbox
```

The container runs an idle loop in the background — it stays up until you explicitly stop it.

**3. Log in to Claude**

```bash
make shell SERVICE=coding-sandbox
```

Inside the container:

```bash
TERM=dumb claude login
```

`TERM=dumb` disables the animation so the OAuth URL prints as plain text.
Copy the `https://` URL from the output, open it in your Mac's browser, log in,
then paste the code back at the prompt.

> **Without `TERM=dumb`:** the animation draws over the URL, making it hard to find.
> You can still scroll up in your terminal to retrieve it, but `TERM=dumb` is easier.

Follow the browser OAuth flow. The session token is stored in the
`icarus-coding-sandbox-claude` named volume and survives container restarts.
You only need to do this once per volume (i.e. after a fresh `make down` with `--volumes`,
or after restoring from backup).

The sandbox uses a **separate Claude account** from your Mac — configure whichever
subscription you want to dedicate to automated/agentic work.

---

## Daily usage

### Open a shell

```bash
make shell SERVICE=coding-sandbox
```

You land in `/workspace` as the `dev` user.

### Run Claude Code interactively

```bash
# From inside the container:
claude
```

Claude Code starts in the current directory. It can read and write any file under
`/workspace`, which maps to `CODING_WORKSPACE` on your Mac (default: `~/Dev`).

### Run a one-shot task

```bash
# From your Mac:
docker exec -it icarus-coding-sandbox claude -p "Add unit tests for src/utils.ts"
```

The `-p` flag (print mode) runs a single prompt non-interactively and exits.

### Run Open Code

```bash
# From inside the container:
opencode
```

Open Code is an alternative TUI for Claude. It uses the same `~/.claude` auth as
Claude Code — no separate login needed.

### Follow logs

```bash
make logs SERVICE=coding-sandbox
```

---

## Working with files

Your code directory (`CODING_WORKSPACE` in `.env`, default `~/Dev`) is mounted
read-write at `/workspace`. All edits Claude makes inside the container appear
immediately on your Mac.

```
Mac path:             ~/Dev/my-project
Container path:       /workspace/my-project
```

Point Claude at a specific project:

```bash
cd /workspace/my-project
claude
```

---

## Networking

The sandbox is on `icarus-net`. It can reach:

- **SearXNG** at `http://searxng:8888` — for web search via Claude's tools
- **Garage S3** at `http://garage:3900` — for object storage access
- **Other icarus-net services** by container name

It cannot reach the internet directly (traffic goes through `icarus-net` — no NAT unless
Docker Desktop's default bridge routing is in play). If you need Claude Code to pull
packages, ensure the required registries are reachable from the host network.

---

## Updating Claude Code

Claude Code updates frequently. To get the latest version, rebuild the image:

```bash
make down SERVICE=coding-sandbox
make build SERVICE=coding-sandbox
make up SERVICE=coding-sandbox
```

Your auth token in the named volume is unaffected by rebuilds — no need to log in again.

---

## Stopping and cleanup

```bash
make down SERVICE=coding-sandbox          # stop, keep volumes
docker compose down --volumes             # stop AND delete all volumes (destroys auth token)
```

---

## Backup

The `icarus-coding-sandbox-claude` volume (auth token + Claude config) is included in
`make backup-all`. To back it up individually:

```bash
make backup VOLUME=icarus-coding-sandbox-claude
```

---

## Troubleshooting

**`claude: command not found`**
The image wasn't built. Run `make build SERVICE=coding-sandbox`.

**`claude login` shows an animation but no visible URL**
Use `TERM=dumb claude login` instead — disables the animation so the URL prints as plain text.

**Session expired inside the container**
Run `make shell SERVICE=coding-sandbox` and `claude login` again.

**File permission errors in `/workspace`**
The `dev` user is UID 1000. If your Mac user has a different UID, files created inside
the container may show as owned by a different user on the host. This is cosmetic — both
can read and write the files.
