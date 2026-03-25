.PHONY: deploy stop restart logs status onboard update validate infra-up infra-down help

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
	@# Health check — runs curl in a sidecar on the same Docker network
	@health_path=$$(grep '^health:' $(app_yaml) | awk '{print $$2}'); \
	health_port=$$(grep '^port:' $(app_yaml) | awk '{print $$2}'); \
	if [ -n "$$health_path" ] && [ -n "$$health_port" ]; then \
		container=$$($(DOCKER_CMD) ps --filter "label=com.docker.compose.project=$(name)" --format '{{.Names}}' | head -1); \
		if [ -z "$$container" ]; then \
			echo "==> WARNING: no container found for $(name)"; \
			exit 1; \
		fi; \
		echo "==> Waiting for health check ($$container:$$health_port$$health_path)..."; \
		for i in $$(seq 1 30); do \
			if $(DOCKER_CMD) run --rm --network=traefik curlimages/curl:latest \
				-sf "http://$$container:$$health_port$$health_path" > /dev/null 2>&1; then \
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

onboard: ## Onboard a new app. Usage: make onboard repo=https://github.com/user/app name=myapp [port=8080]
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	@if [ -z "$(repo)" ]; then echo "Error: repo is required"; exit 1; fi
	@if [ -d "apps/$(name)" ]; then echo "Error: apps/$(name) already exists"; exit 1; fi
	@echo "==> Onboarding $(name) from $(repo)..."
	mkdir -p apps/$(name)
	git clone --depth 1 $(repo) apps/$(name)/src
	@# Validate the cloned repo has what we need
	@if [ ! -f apps/$(name)/src/Dockerfile ] && [ ! -f apps/$(name)/src/docker-compose.yml ]; then \
		echo "WARNING: no Dockerfile or docker-compose.yml found in repo"; \
	fi
	@# Detect port from Dockerfile EXPOSE if not specified
	$(eval app_port := $(or $(port),$(shell grep -i '^EXPOSE' apps/$(name)/src/Dockerfile 2>/dev/null | head -1 | awk '{print $$2}'),8080))
	@# Generate app yaml
	@echo "enabled: true" > $(app_yaml)
	@echo "repo: $(repo)" >> $(app_yaml)
	@echo "image: ghcr.io/be-pongit/$(name)" >> $(app_yaml)
	@echo "domain: $(name).pongit.be" >> $(app_yaml)
	@echo "health: /health" >> $(app_yaml)
	@echo "port: $(app_port)" >> $(app_yaml)
	@# Generate docker-compose.override.yml
	@printf 'services:\n' > $(app_override)
	@printf '  $(name):\n' >> $(app_override)
	@printf '    ports: !override []\n' >> $(app_override)
	@printf '    labels:\n' >> $(app_override)
	@printf '      - "traefik.enable=true"\n' >> $(app_override)
	@printf '      - "traefik.http.routers.$(name).rule=Host(\x60$(name).pongit.be\x60)"\n' >> $(app_override)
	@printf '      - "traefik.http.routers.$(name).tls.certresolver=letsencrypt"\n' >> $(app_override)
	@printf '      - "traefik.http.services.$(name).loadbalancer.server.port=$(app_port)"\n' >> $(app_override)
	@printf '    env_file:\n' >> $(app_override)
	@printf '      - path: ../$(name).env.dec\n' >> $(app_override)
	@printf '        required: false\n' >> $(app_override)
	@printf '    networks:\n' >> $(app_override)
	@printf '      - traefik\n' >> $(app_override)
	@printf '\nnetworks:\n' >> $(app_override)
	@printf '  traefik:\n' >> $(app_override)
	@printf '    external: true\n' >> $(app_override)
	@# Generate empty env file
	@printf '# Environment variables for $(name)\n' > $(app_env)
	@echo ""
	@echo "==> Onboarded $(name)"
	@echo "    $(app_yaml)"
	@echo "    $(app_override)"
	@echo "    $(app_env)"
	@echo ""
	@echo "==> Review the generated files, then: make deploy name=$(name) build=local"

update: ## Update app source from git. Usage: make update name=hello-world
	@if [ -z "$(name)" ]; then echo "Error: name is required"; exit 1; fi
	@if [ ! -d "$(app_src)/.git" ]; then echo "Error: $(app_src) is not a git repo"; exit 1; fi
	@echo "==> Updating $(name) source..."
	git -C $(app_src) pull
	@echo "==> $(name) source updated. Deploy with: make deploy name=$(name) build=local"

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
	@# Decrypt infra secrets if SOPS-encrypted
	@if [ -f secrets/infra.env ]; then \
		if head -1 secrets/infra.env | grep -q "^sops_"; then \
			echo "  Decrypting infra secrets..."; \
			sops -d secrets/infra.env > secrets/infra.env.dec; \
		else \
			cp secrets/infra.env secrets/infra.env.dec; \
		fi; \
		export $$(grep -v '^\s*#' secrets/infra.env.dec | xargs); \
	fi; \
	for dir in infra/*/; do \
		svc=$$(basename $$dir); \
		if [ -f "$$dir/docker-compose.yml" ]; then \
			echo "  Starting $$svc..."; \
			$(COMPOSE_CMD) -f $$dir/docker-compose.yml -p $$svc up -d; \
		fi; \
	done; \
	rm -f secrets/infra.env.dec
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
