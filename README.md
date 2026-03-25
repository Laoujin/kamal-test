# paas-deploy

A minimal PaaS for self-hosting apps on a Synology NAS. Each app is defined by three files in this repo — the app repos themselves stay unaware of infrastructure.

## Prerequisites

- **Docker** with `docker compose` (v2) on the deploy target (Synology or local)
- **SOPS + age** for secrets encryption (when ready)
- **Git** for cloning app repos
- Your user in the `docker` group (`sudo usermod -aG docker $USER`)

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/be-pongit/paas-deploy.git
cd paas-deploy

# 2. Create the shared traefik network
docker network create traefik

# 3. Start infrastructure (Traefik, Pi-hole, Grafana, etc.)
make infra-up

# 4. Deploy the hello-world test app
make deploy name=hello-world build=local

# 5. Verify
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
│   ├── traefik/
│   ├── pihole/
│   ├── grafana/
│   ├── loki/
│   ├── vaultwarden/
│   └── uptime-kuma/
├── secrets/                              # shared infra secrets (SOPS encrypted)
├── docs/
│   └── architecture.md
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
make logs name=myapp                         # tail app logs
make status                                  # show all apps & running containers
make onboard repo=https://github.com/... name=myapp  # scaffold a new app
make infra-up                                # start all infrastructure services
make infra-down                              # stop all infrastructure services
```

## Onboarding a New App

```bash
# 1. Scaffold the app directory
make onboard repo=https://github.com/be-pongit/myapi name=myapi

# 2. Edit the generated files
#    apps/myapi/myapi.yaml         — set domain, image
#    apps/myapi/docker-compose.override.yml — add Traefik labels, env_file, networks
#    apps/myapi/myapi.env          — add secrets (encrypt with SOPS for production)

# 3. Deploy
make deploy name=myapi build=local
```

### The Three Files Per App

| File | Purpose |
|---|---|
| `{app}.yaml` | App metadata: enabled flag, repo URL, image name, domain |
| `docker-compose.override.yml` | Platform concerns: Traefik routing, secrets injection, network attachment |
| `{app}.env` | Environment variables / secrets, SOPS-encrypted at rest |

The app's own `docker-compose.yml` lives in `src/` and is never modified — the override file layers on top of it.

## Deployment Flow

```
Developer pushes to app repo
  → GitHub Actions builds image → pushes to GHCR
    → GitHub's job is done

Developer deploys from local machine
  → make deploy name={app}
    → docker compose pull + up -d
      → Traefik auto-discovers the container via labels
```

For local development or apps without CI, use `build=local` to build from source.

## Setup on a Fresh Synology

### 1. Docker

Install Docker via the Synology Package Center, or manually:
- Ensure Docker Engine and `docker compose` v2 are available
- Add your SSH user to the `docker` group

### 2. SSH Access

```bash
# On your dev machine, copy your public key to the Synology
ssh-copy-id your-user@synology-ip
```

### 3. Networking

```bash
# Create the shared Traefik network (once)
docker network create traefik
```

### 4. DNS

- Point `*.pongit.be` (or individual subdomains) to the Synology's public IP
- Forward ports **80** and **443** on your router to the Synology

### 5. Infrastructure

```bash
# Start Traefik, Pi-hole, Grafana, Loki, etc.
make infra-up
```

### 6. Secrets (SOPS + age)

```bash
# Generate an age key (once)
age-keygen -o ~/.config/sops/age/keys.txt

# Add the public key to .sops.yaml in this repo
# Encrypt an env file
sops -e --in-place apps/myapp/myapp.env

# Decrypt before deploy (automated in future)
sops -d apps/myapp/myapp.env > /tmp/myapp.env
```

## Design Principles

- **Synology is a dumb Docker host.** No custom code on the NAS — everything lives in git.
- **GitHub never touches the Synology.** CI builds images, that's it. You deploy manually.
- **App repos are unaware of infrastructure.** All platform config lives here.
- **Three files per app.** Minimal surface area, easy to audit.

See [docs/architecture.md](docs/architecture.md) for the full architecture and stack decisions.
