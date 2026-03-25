.PHONY: deploy onboard status logs infra-up infra-down help

SHELL := /bin/bash

# Parse app config
app_yaml = apps/$(name)/$(name).yaml
app_src = apps/$(name)/src
app_override = apps/$(name)/docker-compose.override.yml
app_env = apps/$(name)/$(name).env

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

deploy: ## Deploy an app. Usage: make deploy name=hello-world [build=local] [tag=v2026-03-25-abc1234]
	@if [ -z "$(name)" ]; then echo "Error: name is required. Usage: make deploy name=hello-world"; exit 1; fi
	@if [ ! -f $(app_yaml) ]; then echo "Error: $(app_yaml) not found"; exit 1; fi
	@enabled=$$(grep '^enabled:' $(app_yaml) | awk '{print $$2}'); \
	if [ "$$enabled" != "true" ]; then echo "App '$(name)' is disabled. Set enabled: true in $(app_yaml)"; exit 1; fi
	@echo "==> Deploying $(name)..."
	@if [ "$(build)" = "local" ]; then \
		echo "==> Building locally..."; \
		docker compose -f $(app_src)/docker-compose.yml -f $(app_override) build; \
	elif [ -n "$(tag)" ]; then \
		echo "==> Using tag: $(tag)"; \
	else \
		echo "==> Pulling latest image..."; \
		docker compose -f $(app_src)/docker-compose.yml -f $(app_override) pull; \
	fi
	@echo "==> Starting containers..."
	docker compose -f $(app_src)/docker-compose.yml -f $(app_override) \
		-p $(name) up -d
	@echo "==> $(name) deployed successfully"

stop: ## Stop an app. Usage: make stop name=hello-world
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	docker compose -f $(app_src)/docker-compose.yml -f $(app_override) \
		-p $(name) down

logs: ## Tail logs for an app. Usage: make logs name=hello-world
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	docker compose -f $(app_src)/docker-compose.yml -f $(app_override) \
		-p $(name) logs -f

status: ## Show status of all apps
	@echo "==> App Status"
	@echo ""
	@for dir in apps/*/; do \
		app=$$(basename $$dir); \
		yaml="$$dir$$app.yaml"; \
		if [ -f "$$yaml" ]; then \
			enabled=$$(grep '^enabled:' $$yaml | awk '{print $$2}'); \
			if [ "$$enabled" = "true" ]; then \
				status="ENABLED"; \
			else \
				status="DISABLED"; \
			fi; \
			printf "  %-20s %s\n" "$$app" "$$status"; \
		fi; \
	done
	@echo ""
	@echo "==> Running Containers"
	@docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

onboard: ## Onboard a new app. Usage: make onboard repo=https://github.com/user/app name=myapp
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	@if [ -z "$(repo)" ]; then echo "Error: repo is required"; exit 1; fi
	@if [ -d "apps/$(name)" ]; then echo "Error: apps/$(name) already exists"; exit 1; fi
	@echo "==> Onboarding $(name) from $(repo)..."
	mkdir -p apps/$(name)
	git clone --depth 1 $(repo) apps/$(name)/src
	@echo "enabled: true" > apps/$(name)/$(name).yaml
	@echo "repo: $(repo)" >> apps/$(name)/$(name).yaml
	@echo "image: ghcr.io/be-pongit/$(name)" >> apps/$(name)/$(name).yaml
	@echo "domain: $(name).pongit.be" >> apps/$(name)/$(name).yaml
	@echo "==> Created $(app_yaml) — edit domain and image as needed"
	@echo "==> Create $(app_override) with Traefik labels"
	@echo "==> Create $(app_env) with SOPS-encrypted secrets"
	@echo "==> Done. Deploy with: make deploy name=$(name) build=local"

infra-up: ## Start all infrastructure services
	@echo "==> Starting infrastructure..."
	@for dir in infra/*/; do \
		svc=$$(basename $$dir); \
		if [ -f "$$dir/docker-compose.yml" ]; then \
			echo "  Starting $$svc..."; \
			docker compose -f $$dir/docker-compose.yml -p $$svc up -d; \
		fi; \
	done
	@echo "==> Infrastructure up"

infra-down: ## Stop all infrastructure services
	@echo "==> Stopping infrastructure..."
	@for dir in infra/*/; do \
		svc=$$(basename $$dir); \
		if [ -f "$$dir/docker-compose.yml" ]; then \
			echo "  Stopping $$svc..."; \
			docker compose -f $$dir/docker-compose.yml -p $$svc down; \
		fi; \
	done
	@echo "==> Infrastructure down"
