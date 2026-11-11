# Everyday commands on the server. Run from /srv/homeserver: `make` lists them.
# (Needs the docker group: log out and back in once after bootstrap.)

COMPOSE := docker compose -f infra/compose.yaml
S ?=

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  %-16s %s\n", $$1, $$2 }'

# ------------------------------------------------------------------ infra stack --

.PHONY: up update ps logs
up: ## Start (or apply changes to) Caddy, Dockge and Uptime Kuma
	$(COMPOSE) up -d

update: ## Pull newer infra images (same major version) and restart what changed
	$(COMPOSE) pull
	$(COMPOSE) up -d
	docker image prune -f

ps: ## Every container on the server, with its state
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'

logs: ## Follow the infra logs (one service: make logs S=caddy)
	$(COMPOSE) logs -f --tail=100 $(S)

# ------------------------------------------------------------------------ caddy --

.PHONY: caddy-validate caddy-reload
caddy-validate: ## Check infra/caddy/Caddyfile and sites/*.caddy
	docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

caddy-reload: caddy-validate ## Validate, then apply the Caddy configuration without downtime
	docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

# ------------------------------------------------------------------------- mdns --

.PHONY: aliases
aliases: ## State of the mDNS names and the address each one resolves to
	@systemctl --no-pager --lines=5 status homeserver-mdns-aliases || true
	@echo
	@for name in $$(hostname) $$(sed -e 's/#.*//' infra/mdns/aliases); do \
		avahi-resolve -4 -n "$$name.local" || echo "$$name.local: NOT resolved"; \
	done

# ----------------------------------------------------------------------- backup --

.PHONY: backup snapshots test-restore
backup: ## Back up now (as the nightly timer does), showing the output
	sudo scripts/backup.sh run

snapshots: ## List the backup snapshots
	sudo scripts/backup.sh snapshots

test-restore: ## Restore /srv/homeserver from the latest snapshot to a temp dir and compare
	sudo scripts/backup.sh test-restore

# ------------------------------------------------------------------------- lint --

.PHONY: lint
lint: ## shellcheck + yamllint, as in CI (tools from scripts/dev-tools.sh)
	shellcheck -x scripts/*.sh scripts/lib/*.sh
	yamllint --strict .
