#!/usr/bin/env bash
# Scaffold a new service. Prints a checklist and generates a compose block template.

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <service-name>"
  exit 1
fi

NAME="$1"

cat <<EOF

==> New service: $NAME

Paste this block into docker-compose.yml and adjust as needed:

  # ---------------------------------------------------------------------------
  # $NAME
  # ---------------------------------------------------------------------------
  $NAME:
    image: <image>:<tag>
    container_name: icarus-$NAME
    profiles: [$NAME]
    restart: unless-stopped
    # Choose one network:
    #   icarus-net — main stack (most services)
    #   ai-net     — AI cluster only (only open-webui, openhands)
    networks:
      - icarus-net
    ports:
      - "127.0.0.1:<host-port>:<container-port>"
    volumes:
      - icarus-$NAME-data:/data
    environment:
      EXAMPLE_VAR: \${EXAMPLE_VAR:?EXAMPLE_VAR is required}

Checklist:
  1. Paste compose block above into docker-compose.yml
  2. Add volume to top-level volumes: block:
       icarus-$NAME-data:
  3. Add port var and any new secrets to .env.example with generation instructions
  4. If service needs Postgres: add to services/postgres/init/01-create-databases.sql
       CREATE DATABASE $NAME;
     Then add profiles [$NAME] to the postgres service
  5. Add icarus-$NAME-data to VOLUMES list in scripts/backup-all.sh and Makefile
  6. Add URL to the open: target in Makefile
  7. Test: make up SERVICE=$NAME && make open SERVICE=$NAME
  8. Commit

Network guidance:
  - Use icarus-net for anything that is NOT an AI agent or LLM interface.
  - Use ai-net ONLY for open-webui and openhands (and future AI frontends).
  - If the service needs to be reachable from ai-net, add a network alias
    under the ai-net key (see searxng and garage in docker-compose.yml).
  - All ports bind to 127.0.0.1 — no exceptions.

EOF
