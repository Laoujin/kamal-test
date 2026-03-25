# Setup Guide

## What You Need

- Synology with Docker installed
- SSH access to the Synology
- A domain (pongit.be) with DNS you can edit
- A dev machine (your WSL Ubuntu)

## Steps

### 1. Synology: Docker group

SSH into the Synology and add your user to the docker group:

```bash
ssh wouter@<synology-ip>
sudo usermod -aG docker wouter
# Log out and back in for it to take effect
exit
ssh wouter@<synology-ip>
docker ps  # should work without sudo
```

### 2. Synology: Create the traefik network

```bash
ssh wouter@<synology-ip>
docker network create traefik
```

### 3. DNS: Point domains to Synology

In your DNS provider, add:

```
A  traefik.pongit.be     → <synology-public-ip>
A  hello-world.pongit.be → <synology-public-ip>
```

Or a wildcard:

```
A  *.pongit.be → <synology-public-ip>
```

### 4. Router: Forward ports

Forward these ports to the Synology's local IP:

```
80  → <synology-local-ip>:80
443 → <synology-local-ip>:443
```

### 5. Dev machine: SSH key access

```bash
ssh-copy-id wouter@<synology-ip>
# Test it
ssh wouter@<synology-ip> "docker ps"
```

### 6. Dev machine: Clone the repo

```bash
git clone https://github.com/be-pongit/paas-deploy.git
cd paas-deploy
```

### 7. Start Traefik on the Synology

```bash
make infra-up DEPLOY_HOST=wouter@<synology-ip>
```

This starts Traefik with Let's Encrypt. It auto-creates the traefik network if you skipped step 2.

### 8. Deploy hello-world

```bash
make deploy name=hello-world build=local DEPLOY_HOST=wouter@<synology-ip>
```

### 9. Verify

```bash
curl https://hello-world.pongit.be/
# Should return: Hello World, dev

curl https://hello-world.pongit.be/health
# Should return 200
```

If DNS isn't propagated yet, test directly:

```bash
curl -H "Host: hello-world.pongit.be" http://<synology-ip>:80/
```

### 10. Check status

```bash
make status DEPLOY_HOST=wouter@<synology-ip>
```

## Done

From here on, deploying any app is:

```bash
make deploy name=<app> DEPLOY_HOST=wouter@<synology-ip>
```

## Troubleshooting

**"permission denied" on docker commands**
→ Your user isn't in the docker group. Redo step 1.

**"network traefik not found"**
→ Run `make infra-up` first — it creates the network.

**Let's Encrypt certs not working**
→ Check ports 80/443 are forwarded. Traefik needs port 80 open for the HTTP challenge.

**"connection refused" on curl**
→ Check `make status` to see if the container is running. Check `make logs name=<app>` for errors.

**DEPLOY_HOST not connecting**
→ Test with `ssh wouter@<synology-ip> "docker ps"`. Fix SSH first.
