.PHONY: deploy stop logs status onboard infra-up infra-down help validate

SHELL := /bin/bash

# Remote deploy: set DEPLOY_HOST=user@synology-ip to deploy over SSH
# Docker compose uses DOCKER_HOST under the hood for transparent remote execution
ifdef DEPLOY_HOST
  DOCKER_CMD := DOCKER_HOST=ssh://$(DEPLOY_HOST) docker
  COMPOSE_CMD := DOCKER_HOST=ssh://$(DEPLOY_HOST) docker compose
else
  DOCKER_CMD := docker
  COMPOSE_CMD := docker compose
endif

# Parse app config
app_dir    = apps/$(name)
app_yaml   = $(app_dir)/$(name).yaml
app_src    = $(app_dir)/src
app_override = $(app_dir)/docker-compose.override.yml
app_env    = $(app_dir)/$(name).env
app_env_dec = $(app_dir)/$(name).env.dec
app_tag_override = $(app_dir)/.docker-compose.tag.yml

# Compose file args (tag override added dynamically in deploy target)
compose_files = -f $(app_src)/docker-compose.yml -f $(app_override)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

deploy: ## Deploy an app. Usage: make deploy name=hello-world [build=local] [tag=v2026-03-25-abc] [DEPLOY_HOST=user@host]
	@if [ -z "$(name)" ]; then echo "Error: name is required. Usage: make deploy name=hello-world"; exit 1; fi
	@if [ ! -f $(app_yaml) ]; then echo "Error: $(app_yaml) not found"; exit 1; fi
	@enabled=$$(grep '^enabled:' $(app_yaml) | awk '{print $$2}'); \
	if [ "$$enabled" != "true" ]; then echo "App '$(name)' is disabled. Set enabled: true in $(app_yaml)"; exit 1; fi
	@# Decrypt secrets if SOPS-encrypted
	@if [ -f $(app_env) ]; then \
		if head -1 $(app_env) | grep -q "^sops_"; then \
			echo "==> Decrypting secrets..."; \
			sops -d $(app_env) > $(app_env_dec); \
		else \
			cp $(app_env) $(app_env_dec); \
		fi; \
	fi
	@# Build compose file list
	$(eval extra_files :=)
	@echo "==> Deploying $(name)..."
	@if [ "$(build)" = "local" ]; then \
		echo "==> Building locally..."; \
		$(COMPOSE_CMD) $(compose_files) build; \
	elif [ -n "$(tag)" ]; then \
		image=$$(grep '^image:' $(app_yaml) | awk '{print $$2}'); \
		echo "==> Using image: $$image:$(tag)"; \
		svc=$$(grep -E '^\s+\S+:$$' $(app_src)/docker-compose.yml | head -1 | tr -d ' :'); \
		printf "services:\n  $$svc:\n    image: $$image:$(tag)\n" > $(app_tag_override); \
		$(COMPOSE_CMD) $(compose_files) -f $(app_tag_override) pull; \
	else \
		echo "==> Pulling latest image..."; \
		$(COMPOSE_CMD) $(compose_files) pull; \
	fi
	@echo "==> Starting containers..."
	@if [ -n "$(tag)" ] && [ -f $(app_tag_override) ]; then \
		$(COMPOSE_CMD) $(compose_files) -f $(app_tag_override) -p $(name) up -d; \
	else \
		$(COMPOSE_CMD) $(compose_files) -p $(name) up -d; \
	fi
	@# Health check
	@health_url=$$(grep '^health:' $(app_yaml) | awk '{print $$2}'); \
	if [ -n "$$health_url" ]; then \
		echo "==> Waiting for health check ($$health_url)..."; \
		for i in $$(seq 1 30); do \
			if curl -sf "$$health_url" > /dev/null 2>&1; then \
				echo "==> $(name) is healthy"; \
				break; \
			fi; \
			if [ $$i -eq 30 ]; then \
				echo "==> WARNING: health check failed after 30s"; \
				$(COMPOSE_CMD) $(compose_files) -p $(name) logs --tail=20; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
	else \
		echo "==> $(name) deployed (no health check configured)"; \
	fi
	@# Cleanup temp files
	@rm -f $(app_env_dec) $(app_tag_override)

stop: ## Stop an app. Usage: make stop name=hello-world
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	$(COMPOSE_CMD) $(compose_files) -p $(name) down

restart: ## Restart an app. Usage: make restart name=hello-world
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	$(COMPOSE_CMD) $(compose_files) -p $(name) restart

logs: ## Tail logs for an app. Usage: make logs name=hello-world
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	$(COMPOSE_CMD) $(compose_files) -p $(name) logs -f

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
	@$(DOCKER_CMD) ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

onboard: ## Onboard a new app. Usage: make onboard repo=https://github.com/user/app name=myapp
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	@if [ -z "$(repo)" ]; then echo "Error: repo is required"; exit 1; fi
	@if [ -d "apps/$(name)" ]; then echo "Error: apps/$(name) already exists"; exit 1; fi
	@echo "==> Onboarding $(name) from $(repo)..."
	mkdir -p apps/$(name)
	git clone --depth 1 $(repo) apps/$(name)/src
	@echo "enabled: true" > $(app_yaml)
	@echo "repo: $(repo)" >> $(app_yaml)
	@echo "image: ghcr.io/be-pongit/$(name)" >> $(app_yaml)
	@echo "domain: $(name).pongit.be" >> $(app_yaml)
	@echo "==> Created $(app_yaml) — edit domain and image as needed"
	@echo "==> Create $(app_override) with Traefik labels"
	@echo "==> Create $(app_env) with secrets"
	@echo "==> Done. Deploy with: make deploy name=$(name) build=local"

validate: ## Validate all app configs
	@echo "==> Validating app configs..."
	@errors=0; \
	for dir in apps/*/; do \
		app=$$(basename $$dir); \
		yaml="$$dir$$app.yaml"; \
		override="$$dir/docker-compose.override.yml"; \
		src_compose="$$dir/src/docker-compose.yml"; \
		if [ ! -f "$$yaml" ]; then \
			echo "  FAIL  $$app: missing $$yaml"; errors=$$((errors+1)); \
		else \
			echo "  OK    $$app: $$yaml"; \
		fi; \
		if [ ! -f "$$override" ]; then \
			echo "  FAIL  $$app: missing docker-compose.override.yml"; errors=$$((errors+1)); \
		else \
			echo "  OK    $$app: docker-compose.override.yml"; \
		fi; \
		if [ ! -f "$$src_compose" ]; then \
			echo "  FAIL  $$app: missing src/docker-compose.yml"; errors=$$((errors+1)); \
		else \
			echo "  OK    $$app: src/docker-compose.yml"; \
		fi; \
		if [ -f "$$src_compose" ] && [ -f "$$override" ]; then \
			if docker compose -f "$$src_compose" -f "$$override" config > /dev/null 2>&1; then \
				echo "  OK    $$app: compose config valid"; \
			else \
				echo "  FAIL  $$app: compose config invalid"; errors=$$((errors+1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	if [ $$errors -gt 0 ]; then \
		echo "==> $$errors error(s) found"; exit 1; \
	else \
		echo "==> All apps valid"; \
	fi

infra-up: ## Start all infrastructure services
	@echo "==> Starting infrastructure..."
	@# Ensure traefik network exists
	@$(DOCKER_CMD) network inspect traefik >/dev/null 2>&1 || $(DOCKER_CMD) network create traefik
	@for dir in infra/*/; do \
		svc=$$(basename $$dir); \
		if [ -f "$$dir/docker-compose.yml" ]; then \
			echo "  Starting $$svc..."; \
			$(COMPOSE_CMD) -f $$dir/docker-compose.yml -p $$svc up -d; \
		fi; \
	done
	@echo "==> Infrastructure up"

infra-down: ## Stop all infrastructure services
	@echo "==> Stopping infrastructure..."
	@for dir in infra/*/; do \
		svc=$$(basename $$dir); \
		if [ -f "$$dir/docker-compose.yml" ]; then \
			echo "  Stopping $$svc..."; \
			$(COMPOSE_CMD) -f $$dir/docker-compose.yml -p $$svc down; \
		fi; \
	done
	@echo "==> Infrastructure down"
