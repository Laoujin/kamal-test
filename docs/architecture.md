# PaaS Deploy — Architecture

## Principles

- **Synology is a dumb target.** No custom code on the Synology, everything in git.
- **GitHub never touches the Synology.** No SSH from GitHub Actions. CI builds & pushes images to GHCR, that's it.
- **You deploy manually from your machine.** You decide when, via Makefile commands over SSH.
- **Three files per app** in this repo. App repos stay unaware of infrastructure.

## MVP Stack

| Component | Tool | Notes |
|---|---|---|
| Reverse proxy + HTTPS | Traefik | Auto-discovery, Let's Encrypt, custom domains on `*.pongit.be` |
| DNS + ad-blocking | Pi-hole | Local DNS + ad blocking |
| Secrets (deploy-time) | SOPS + age | Encrypted env files in git, decrypted at deploy time |
| Personal passwords | Vaultwarden | Browser extension, mobile app, behind Traefik with HTTPS |
| Log aggregation | Grafana + Loki + Alloy | Centralized logging, dashboards |
| Uptime monitoring | Uptime Kuma | Purpose-built uptime monitoring with alerts |
| Deploy UI (evaluate) | Dockge | Under evaluation, may or may not keep |
| Networking | Unifi Cloud Key Gen2 | To be set up, feed metrics into Grafana |
| Deployment | Makefile + docker-compose overrides | Simple CLI commands |
| CI | GitHub Actions → GHCR | Build images, tag, push. Done. |
| Backups | TBD | Encrypted, to Synology #2 or cloud |

## Versioning

Automatic, date-based tags with git SHA: `v2026-03-25-a1b2c3d`

Generated in GitHub Actions, no manual tag management.

## Deployment Flow

```
Developer pushes code to app repo
  → GitHub Actions builds Docker image
    → Tags: ghcr.io/be-pongit/{app}:v{date}-{sha} + :latest
      → Pushes to GHCR
        → GitHub's job is OVER

Developer decides to deploy (from local machine)
  → make deploy name={app}
    → SSH to Synology
      → Decrypts SOPS secrets
        → docker compose pull && up -d
          → Cleans up decrypted secrets
```

## Repository Structure

```
paas-deploy/
├── infra/
│   ├── traefik/
│   │   └── docker-compose.yml
│   ├── pihole/
│   │   └── docker-compose.yml
│   ├── grafana/
│   │   └── docker-compose.yml
│   ├── loki/
│   │   └── docker-compose.yml
│   ├── vaultwarden/
│   │   └── docker-compose.yml
│   └── uptime-kuma/
│       └── docker-compose.yml
│
├── apps/
│   ├── {app-name}/
│   │   ├── {app-name}.yaml                 # config: repo, image, domain, environments
│   │   ├── docker-compose.override.yml      # Traefik labels, secrets, networking
│   │   ├── {app-name}.env                   # SOPS-encrypted secrets
│   │   └── src/                             # sparse clone of app repo
│   │       └── docker-compose.yml           # from app repo (not modified)
│   └── ...
│
├── secrets/                                 # shared infra secrets (SOPS encrypted)
├── docs/
│   └── architecture.md
├── Makefile
├── .sops.yaml
└── README.md
```

## App Configuration — Three Files

### `{app-name}.yaml` — Where to find things
```yaml
enabled: true
repo: https://github.com/be-pongit/{app-name}
image: ghcr.io/be-pongit/{app-name}
domain: {app-name}.pongit.be
```

### `docker-compose.override.yml` — How to run it on the platform
Adds Traefik labels, env_file reference, and network config.
Docker Compose automatically merges this with the app's own `docker-compose.yml`.

### `{app-name}.env` — Secrets (SOPS encrypted)
Key-value pairs, encrypted at rest, decrypted at deploy time, injected as environment variables.

## Multi-Environment Support

For apps that deploy to multiple Synologies (e.g., test + prd):

```
apps/special-app/
├── special-app.yaml              # environments: test, prd with different hosts/domains
├── docker-compose.override.yml   # shared overrides
├── docker-compose.override.prd.yml  # prd-specific overrides (if needed)
├── special-app.test.env          # SOPS encrypted, test secrets
├── special-app.prd.env           # SOPS encrypted, prd secrets
└── src/
```

```bash
make deploy name=special-app              # deploys to default (test)
make deploy name=special-app env=prd      # deploys to prd
```

## Makefile Commands

```bash
make onboard repo=https://github.com/be-pongit/myapi name=myapi   # clone repo, create secrets
make deploy name=myapi                     # pull image & deploy
make deploy name=myapi local              # build locally & deploy
make deploy name=myapi tag=v2026-03-25-abc1234  # deploy specific version
make status                                # show all running apps & versions
make logs name=myapi                       # tail logs
make infra-up                              # start all infrastructure
```

## Post-MVP (parked)

- Auth: Authelia / Authentik (SSO, Google login)
- Home automation: Home Assistant
- Photos: Immich / PhotoPrism
- 3D printer: OctoPrint
- PDF tools: Stirling-PDF
- Workflow automation: n8n
- Document management: Paperless-ngx
- Nextcloud
- All Docker logs → Loki
- All Synology logs → Grafana (Netdata?)
- Pi-hole dashboard in Grafana
- Prometheus for metrics

## Constraints

- Synology has 6GB RAM (~5GB usable after OS)
- MVP infra estimated at ~800MB
- Single operator (Wouter)
- Domain: pongit.be
- Two Synologies available, but everything on one unless specified
