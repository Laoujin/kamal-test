# paas-deploy

Minimal dotnet API to test the Kamal deployment pipeline.

## Pipeline

1. Push to `master` → CI builds Docker image → pushes to GHCR
2. Go to Actions → "Deploy" → click "Run workflow" → Kamal deploys to Synology

## One-time setup

### Synology
1. Install Docker on Synology
2. Ensure SSH access is enabled
3. Add your SSH public key to `~/.ssh/authorized_keys` on the Synology

### Vaultwarden (optional, for secrets)
```bash
docker run -d --name vaultwarden \
  -v /volume1/docker/vaultwarden:/data \
  -p 8222:80 \
  --restart always \
  vaultwarden/server:latest
```

### DNS
Point `test.pongit.be` to your Synology's public IP.
Forward ports 80 and 443 on your router to the Synology.

### GitHub
1. Create repo `be-pongit/paas-deploy`
2. Add repository secrets:
   - `SSH_PRIVATE_KEY` — private key for Synology SSH access
   - `SYNOLOGY_HOST` — Synology IP or hostname

### Kamal bootstrap (run once from your dev machine)
```bash
gem install kamal
# Edit config/deploy.yml with your Synology IP and SSH user
kamal setup
```

### config/deploy.yml
Update the placeholder values:
- `SYNOLOGY_IP_HERE` → your Synology's IP
- `SYNOLOGY_USER_HERE` → SSH username

## Local development

```bash
cd src
dotnet run
# http://localhost:5000
```

## Local Docker test

```bash
docker build -t paas-deploy .
docker run -p 8080:8080 paas-deploy
# http://localhost:8080
```
