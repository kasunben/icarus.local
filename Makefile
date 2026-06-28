.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Service management
# ---------------------------------------------------------------------------

up: ## Start a service: make up SERVICE=<name>
	@test -n "$(SERVICE)" || (echo "Usage: make up SERVICE=<name>" && exit 1)
	docker compose --profile $(SERVICE) up -d

down: ## Stop a service: make down SERVICE=<name>
	@test -n "$(SERVICE)" || (echo "Usage: make down SERVICE=<name>" && exit 1)
	docker compose --profile $(SERVICE) down

restart: ## Restart a service: make restart SERVICE=<name>
	@test -n "$(SERVICE)" || (echo "Usage: make restart SERVICE=<name>" && exit 1)
	docker compose --profile $(SERVICE) restart

logs: ## Follow logs: make logs SERVICE=<name>
	@test -n "$(SERVICE)" || (echo "Usage: make logs SERVICE=<name>" && exit 1)
	docker compose logs -f $(SERVICE)

shell: ## Open bash shell in container: make shell SERVICE=<name>
	@test -n "$(SERVICE)" || (echo "Usage: make shell SERVICE=<name>" && exit 1)
	docker exec -it icarus-$(SERVICE) bash

ps: ## Show running containers
	docker compose ps

build: ## Build a locally-built image: make build SERVICE=<name>
	@test -n "$(SERVICE)" || (echo "Usage: make build SERVICE=<name>" && exit 1)
	docker compose --profile $(SERVICE) build $(SERVICE)

open: ## Print localhost URL for a service: make open SERVICE=<name>
	@test -n "$(SERVICE)" || (echo "Usage: make open SERVICE=<name>" && exit 1)
	@case "$(SERVICE)" in \
		postgres)        echo "Internal only — use: make db-shell DB=<name>" ;; \
		redis)           echo "Internal only" ;; \
		n8n)             echo "http://localhost:5678" ;; \
		nextcloud)       echo "http://localhost:8091" ;; \
		searxng)         echo "http://localhost:8888" ;; \
		garage)          echo "http://localhost:3900  (S3 API)  http://localhost:3903  (Admin API)" ;; \
		open-webui)      echo "http://localhost:3000" ;; \
		openhands)       echo "http://localhost:3100" ;; \
		bentopdf)        echo "http://localhost:8090" ;; \
		changedetection) echo "http://localhost:5000" ;; \
		glances)         echo "http://localhost:61208" ;; \
		pihole)          echo "http://localhost:8053/admin" ;; \
		*)               echo "Unknown service: $(SERVICE)" ;; \
	esac

# ---------------------------------------------------------------------------
# Garage
# ---------------------------------------------------------------------------

garage-init: ## Bootstrap Garage layout (one-time, safe to re-run)
	@echo "==> Checking Garage status..."
	@NODE_ID=$$(docker exec icarus-garage /garage status 2>/dev/null | awk 'NR==2{print $$1}'); \
	if [ -z "$$NODE_ID" ]; then \
		echo "ERROR: Garage container is not running. Run: make up SERVICE=garage"; exit 1; \
	fi; \
	echo "Node ID: $$NODE_ID"; \
	docker exec icarus-garage /garage layout assign --zone local --capacity 50G $$NODE_ID 2>/dev/null || true; \
	if docker exec icarus-garage /garage layout apply --version 1 2>/dev/null; then \
		echo "==> Layout applied."; \
	else \
		echo "==> Layout already applied (or version already used — this is fine)."; \
	fi; \
	docker exec icarus-garage /garage key create icarus-key 2>/dev/null || true; \
	docker exec icarus-garage /garage bucket create icarus 2>/dev/null || true; \
	docker exec icarus-garage /garage bucket allow icarus --read --write --key icarus-key 2>/dev/null || true; \
	echo ""; \
	echo "==> Garage credentials (copy into .env):"; \
	docker exec icarus-garage /garage key info icarus-key

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

db-shell: ## psql into Postgres: make db-shell DB=<name>
	@test -n "$(DB)" || (echo "Usage: make db-shell DB=<name>" && exit 1)
	docker exec -it icarus-postgres psql -U icarus -d $(DB)

db-dump: ## Dump Postgres DB: make db-dump DB=<name>
	@test -n "$(DB)" || (echo "Usage: make db-dump DB=<name>" && exit 1)
	@mkdir -p backups
	docker exec icarus-postgres pg_dump -U icarus $(DB) | gzip > backups/$(DB)_$$(date +%Y%m%d_%H%M%S).sql.gz
	@echo "==> Dumped to backups/$(DB)_*.sql.gz"

db-restore: ## Restore Postgres DB: make db-restore DB=<name> FILE=<path>
	@test -n "$(DB)" || (echo "Usage: make db-restore DB=<name> FILE=<path>" && exit 1)
	@test -n "$(FILE)" || (echo "Usage: make db-restore DB=<name> FILE=<path>" && exit 1)
	gunzip -c $(FILE) | docker exec -i icarus-postgres psql -U icarus -d $(DB)

nextcloud-occ: ## Run occ in Nextcloud: make nextcloud-occ CMD="<occ command>"
	@test -n "$(CMD)" || (echo "Usage: make nextcloud-occ CMD=\"<occ command>\"" && exit 1)
	docker exec -u www-data icarus-nextcloud php occ $(CMD)

# ---------------------------------------------------------------------------
# Backup and restore
# ---------------------------------------------------------------------------

VOLUMES = \
	icarus-postgres-data \
	icarus-redis-data \
	icarus-nextcloud-db-data \
	icarus-nextcloud-data \
	icarus-nextcloud-html \
	icarus-n8n-data \
	icarus-garage-meta \
	icarus-garage-data \
	icarus-searxng-cache \
	icarus-open-webui-data \
	icarus-openhands-data \
	icarus-changedetection-data \
	icarus-pihole-data \
	icarus-pihole-dnsmasq \
	icarus-coding-sandbox-claude

backup-all: ## Backup all volumes and Postgres databases
	./scripts/backup-all.sh

backup: ## Backup a single volume: make backup VOLUME=icarus-<name>
	@test -n "$(VOLUME)" || (echo "Usage: make backup VOLUME=icarus-<name>" && exit 1)
	@mkdir -p backups
	docker run --rm -v $(VOLUME):/data -v $$(pwd)/backups:/backups alpine \
		tar czf /backups/$(VOLUME)_$$(date +%Y%m%d_%H%M%S).tar.gz -C /data .
	@echo "==> Backed up $(VOLUME)"

restore: ## Restore a volume: make restore VOLUME=icarus-<name> FILE=<path>
	@test -n "$(VOLUME)" || (echo "Usage: make restore VOLUME=icarus-<name> FILE=<path>" && exit 1)
	@test -n "$(FILE)" || (echo "Usage: make restore VOLUME=icarus-<name> FILE=<path>" && exit 1)
	docker run --rm -v $(VOLUME):/data -v $$(pwd)/$(FILE):/backup.tar.gz alpine \
		sh -c "cd /data && tar xzf /backup.tar.gz"
	@echo "==> Restored $(VOLUME) from $(FILE)"

# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

init: ## Create .env from .env.example and required directories
	@if [ -f .env ]; then \
		echo ".env already exists — not overwriting."; \
	else \
		cp .env.example .env; \
		echo "==> Created .env from .env.example. Fill in all secrets before starting services."; \
	fi
	@mkdir -p backups

keygen: ## Generate a random encryption key (for N8N_ENCRYPTION_KEY)
	@openssl rand -hex 32

keygen-all: ## Print all required secrets for first-time .env setup
	@echo ""
	@echo "# Paste these into .env (each value is unique — don't reuse)"
	@echo ""
	@echo "POSTGRES_PASSWORD=$$(openssl rand -hex 24)"
	@echo "REDIS_PASSWORD=$$(openssl rand -hex 24)"
	@echo "N8N_ENCRYPTION_KEY=$$(openssl rand -hex 32)"
	@echo "NEXTCLOUD_DB_ROOT_PASSWORD=$$(openssl rand -hex 24)"
	@echo "NEXTCLOUD_DB_PASSWORD=$$(openssl rand -hex 24)"
	@echo "SEARXNG_SECRET_KEY=$$(openssl rand -hex 32)"
	@echo "GARAGE_RPC_SECRET=$$(openssl rand -hex 32)"
	@echo "GARAGE_ADMIN_TOKEN=$$(openssl rand -hex 32)"
	@echo "OPEN_WEBUI_SECRET_KEY=$$(openssl rand -hex 32)"
	@echo ""
	@echo "# Set manually:"
	@echo "PIHOLE_WEBPASSWORD=<strong passphrase>"
	@echo "ANTHROPIC_API_KEY=<from console.anthropic.com>"
	@echo ""
	@echo "# Set after: make garage-init"
	@echo "GARAGE_ACCESS_KEY=<from garage key info>"
	@echo "GARAGE_SECRET_KEY=<from garage key info>"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

help: ## Show this help
	@echo ""
	@echo "icarus.local — on-demand service stack"
	@echo ""
	@echo "Usage:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Services: postgres redis n8n nextcloud searxng garage open-webui openhands"
	@echo "          bentopdf changedetection glances pihole coding-sandbox"
	@echo ""

.PHONY: up down restart logs shell ps build open garage-init \
        db-shell db-dump db-restore nextcloud-occ \
        backup-all backup restore init keygen keygen-all help
