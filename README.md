# paas-deploy

A minimal PaaS for self-hosting apps on a Synology NAS. Each app is defined by three files in this repo — the app repos themselves stay unaware of infrastructure.

## Prerequisites

- **Docker** with `docker compose` v2.24+ on the deploy target
- **Git** for cloning app repos
- Your user in the `docker` group (`sudo usermod -aG docker $USER`)
- **SOPS + age** for secrets encryption (optional, for production)

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/be-pongit/paas-deploy.git
cd paas-deploy

# 2. Create the shared traefik network
docker network create traefik

# 3. Deploy the hello-world test app
make deploy name=hello-world build=local

# 4. Verify
curl http://localhost:8080/        # Hello World, dev
curl http://localhost:8080/health  # 200 OK
```

## Repository Structure

```
paas-deploy/
├── apps/
│   └── {app-name}/
│       ├── {app-name}.yaml              # config: enabled, repo, image, domain
│       ├── docker-compose.override.yml   # Traefik labels, env_file, networking
│       ├── {app-name}.env                # secrets (SOPS-encrypted in production)
│       └── src/                          # app source (cloned from app repo)
│           ├── docker-compose.yml        # from app repo — not modified
│           └── Dockerfile
├── infra/
│   └── traefik/
│       └── docker-compose.yml           # reverse proxy with Let's Encrypt
├── secrets/                              # shared infra secrets (SOPS encrypted)
├── docs/
│   └── architecture.md
├── .github/workflows/
│   └── ci.yml                           # validates configs, tests deploy flow
├── Makefile
└── README.md
```

## Makefile Commands

```bash
make help                                    # show all commands
make deploy name=myapp                       # pull latest image & deploy
make deploy name=myapp build=local           # build locally & deploy
make deploy name=myapp tag=v2026-03-25-abc   # deploy a specific version
make stop name=myapp                         # stop an app
make restart name=myapp                      # restart an app
make logs name=myapp                         # tail app logs
make status                                  # show all apps & running containers
make validate                                # check all app configs are valid
make onboard repo=https://github.com/... name=myapp  # scaffold a new app
make infra-up                                # start all infrastructure services
make infra-down                              # stop all infrastructure services
```

### Remote Deploy

Deploy to a remote host (e.g., your Synology) by setting `DEPLOY_HOST`:

```bash
make deploy name=myapp DEPLOY_HOST=wouter@synology-ip
make status DEPLOY_HOST=wouter@synology-ip
```

This uses Docker's SSH transport — `docker compose` commands run remotely but read compose files locally. Requires SSH key access to the target.

## Onboarding a New App

```bash
# 1. Scaffold the app directory
make onboard repo=https://github.com/be-pongit/myapi name=myapi

# 2. Edit the generated files
#    apps/myapi/myapi.yaml                  — set domain, image
#    apps/myapi/docker-compose.override.yml — add Traefik labels, env_file, networks
#    apps/myapi/myapi.env                   — add secrets

# 3. Deploy
make deploy name=myapi build=local
```

### The Three Files Per App

| File | Purpose |
|---|---|
| `{app}.yaml` | App metadata: enabled flag, repo URL, image name, domain |
| `docker-compose.override.yml` | Platform concerns: Traefik routing, secrets injection, network attachment |
| `{app}.env` | Environment variables / secrets, SOPS-encrypted at rest in production |

The app's own `docker-compose.yml` lives in `src/` and is never modified — the override layers on top.

## Deployment Flow

```
Developer pushes to app repo
  → GitHub Actions builds image → pushes to GHCR
    → GitHub's job is done

Developer deploys (from local machine or CI)
  → make deploy name={app} [DEPLOY_HOST=user@synology]
    → Decrypts secrets (if SOPS-encrypted)
      → docker compose pull + up -d
        → Traefik auto-discovers via labels
          → Cleans up decrypted secrets
```

For local development or apps without CI, use `build=local` to build from source.

## Secrets (SOPS + age)

App secrets live in `{app-name}.env` files. In production these are encrypted with SOPS + age.

```bash
# Generate an age key (once)
age-keygen -o ~/.config/sops/age/keys.txt

# Add the public key to .sops.yaml
# Encrypt
sops -e --in-place apps/myapp/myapp.env

# The Makefile handles decryption automatically during deploy:
# - Detects SOPS-encrypted files by checking the header
# - Decrypts to a temporary .env.dec file
# - Runs docker compose with the decrypted file
# - Cleans up the .env.dec after deploy
```

Unencrypted `.env` files work too — they're copied as-is during deploy.

## Setup on a Fresh Synology

### 1. Docker & SSH

```bash
# Install Docker via Synology Package Center
# Add your user to the docker group
sudo usermod -aG docker your-user

# From your dev machine, set up SSH key access
ssh-copy-id your-user@synology-ip
```

### 2. Networking

```bash
# On the Synology (or via DEPLOY_HOST from your machine)
docker network create traefik
```

### 3. DNS

- Point `*.pongit.be` (or individual subdomains) to the Synology's public IP
- Forward ports **80** and **443** on your router to the Synology

### 4. Infrastructure

```bash
# Start Traefik (creates the network automatically if missing)
make infra-up
# Or target the Synology remotely:
make infra-up DEPLOY_HOST=wouter@synology-ip
```

### 5. Deploy an App

```bash
make deploy name=hello-world build=local DEPLOY_HOST=wouter@synology-ip
```

## CI

GitHub Actions runs on every push and PR to `master`:

- **validate** — checks all apps have the required files and valid compose configs
- **deploy-test** — builds hello-world, deploys it, tests health/root endpoints, tests stop
- **infra-validate** — validates all infrastructure compose files

## Design Principles

- **Synology is a dumb Docker host.** No custom code on the NAS — everything lives in git.
- **GitHub never touches the Synology.** CI builds images, that's it. You deploy manually.
- **App repos are unaware of infrastructure.** All platform config lives here.
- **Three files per app.** Minimal surface area, easy to audit.

See [docs/architecture.md](docs/architecture.md) for the full architecture and stack decisions.
