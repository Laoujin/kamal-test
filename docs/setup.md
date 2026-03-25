# Setup Guide

## What You Need

- Synology with Docker installed
- SSH access to the Synology
- Domain (pongit.be) with DNS you can edit
- Router access for port forwarding

## Steps

### 1. Synology: Docker group

```bash
ssh wouter@<synology-ip>
sudo usermod -aG docker wouter
exit
ssh wouter@<synology-ip>
docker ps  # should work without sudo
```

### 2. Synology: Clone this repo

```bash
ssh wouter@<synology-ip>
git clone https://github.com/be-pongit/paas-deploy.git
cd paas-deploy
```

All `make` commands run here, directly on the Synology.

### 3. Router: Forward ports

Forward to the Synology's local IP:

```
80  → <synology-local-ip>:80
443 → <synology-local-ip>:443
```

### 4. DNS

Add to your DNS provider:

```
A  *.pongit.be → <synology-public-ip>
```

Or individual records if you prefer:

```
A  traefik.pongit.be   → <synology-public-ip>
A  grafana.pongit.be   → <synology-public-ip>
A  vault.pongit.be     → <synology-public-ip>
A  status.pongit.be    → <synology-public-ip>
A  pihole.pongit.be    → <synology-public-ip>
```

### 5. Start infrastructure

```bash
make infra-up
```

This starts Traefik, creates the traefik network, and brings up any other infra services that have compose files.

Verify Traefik is running:

```bash
make status
```

### 6. Deploy hello-world to test

```bash
make deploy name=hello-world build=local
```

You should see the health check pass. Verify:

```bash
curl https://hello-world.pongit.be/
```

### 7. Set up SOPS (for secrets)

On the Synology:

```bash
# Install age
sudo apt install age   # or download from https://github.com/FiloSottile/age/releases

# Install sops
# Download from https://github.com/getsops/sops/releases

# Generate a key
age-keygen -o ~/.config/sops/age/keys.txt
# Note the public key it prints

# Edit .sops.yaml — replace YOUR_AGE_PUBLIC_KEY_HERE with your public key
```

Then encrypt an env file:

```bash
sops -e --in-place apps/hello-world/hello-world.env
```

The Makefile auto-decrypts during deploy and cleans up after.

### 8. Done

Deploy any app:

```bash
make deploy name=<app> build=local    # build from source
make deploy name=<app>                # pull from GHCR
make deploy name=<app> tag=v1.2.3     # specific version
```

Other commands:

```bash
make status              # what's running
make logs name=<app>     # tail logs
make stop name=<app>     # stop an app
make validate            # check all configs
```

## Infra Services

| Service | URL | Notes |
|---|---|---|
| Traefik | traefik.pongit.be | Reverse proxy, Let's Encrypt |
| Grafana | grafana.pongit.be | Dashboards, default password: changeme |
| Uptime Kuma | status.pongit.be | Uptime monitoring |
| Vaultwarden | vault.pongit.be | Password manager, signups disabled by default |
| Pi-hole | pihole.pongit.be | DNS + ad blocking, default password: changeme |
| Loki + Alloy | (internal) | Log aggregation, auto-collects all Docker logs |

Change default passwords by setting env vars before `make infra-up`:

```bash
GRAFANA_PASSWORD=mysecret PIHOLE_PASSWORD=mysecret make infra-up
```

## Troubleshooting

**"permission denied" on docker**
→ `sudo usermod -aG docker wouter`, then log out and back in.

**"network traefik not found"**
→ `make infra-up` creates it automatically. Or: `docker network create traefik`

**Let's Encrypt certs not working**
→ Ports 80+443 must be forwarded. DNS must point to the Synology. Check `make logs name=traefik` (run from infra: `docker compose -f infra/traefik/docker-compose.yml -p traefik logs`).

**Container starts but health check fails**
→ `make logs name=<app>` to see what's crashing.

**Can I deploy from my dev machine instead?**
→ Yes, for pull-based deploys: `make deploy name=<app> DEPLOY_HOST=wouter@<synology-ip>`. Not recommended for `build=local` — it sends the build context over SSH which is slow.
