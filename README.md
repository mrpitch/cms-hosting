# CMS Hosting Docker Boilerplate

Dockerised Next.js 16 runtime with an Nginx reverse proxy, automated TLS via Certbot, and a GitHub Actions pipeline for CI/CD.

## Stack Overview

- `app/` – Default Next.js application configured for standalone builds (`next.config.ts`).
- `deploy/docker/next.Dockerfile` – Multi-stage build producing a lean Node 20 runtime image.
- `deploy/docker/nginx/` – Nginx proxy image with HTTP→HTTPS redirect, ACME challenge handling, and temporary self-signed certificates.
- `deploy/certbot/` – Certbot-based helper image for certificate issuance and renewals.
- `deploy/docker/docker-compose.yml` – Orchestrates the app, proxy, and Certbot services.
- `.github/workflows/deploy.yml` – Lint/test/build, push Docker images to GHCR, optional remote deployment.

## Prerequisites

- Docker Engine 24+ and Docker Compose V2.
- (Optional) Node.js 20+ for local `npm` workflows outside containers.
- A domain name pointing at the host running the stack.
- GitHub repository with permissions to push to GitHub Container Registry (or adjust workflow for your registry).

## Environment Variables

Create a runtime environment file for the Next.js container.

```bash
cp deploy/docker/env.example deploy/docker/app.env
```

Key variables:

- `NODE_ENV` – defaults to `production` inside the container.
- `PORT` – Next.js internal port (default `3000`).
- `NEXT_PUBLIC_SITE_URL` – Public site origin (used in the app).
- `DOMAIN`, `DOMAINS`, `SSL_EMAIL` – Used by Nginx and Certbot to locate certificates and register with Let’s Encrypt.

> Docker Compose automatically loads `deploy/docker/app.env` and `.env` (if present) when you run the stack.

## Local Development with Docker

1. Copy the example env file as shown above and adjust values for your environment (e.g. `DOMAIN=localhost`, `NEXT_PUBLIC_SITE_URL=https://localhost`).
2. Start the stack:

   ```bash
   docker compose -f deploy/docker/docker-compose.yml up --build
   ```

3. Access the app via `https://localhost`. The proxy presents a short-lived self-signed certificate until Let’s Encrypt certificates are issued. Trust it locally or use a tool like `mkcert`.
4. Hot reload is disabled in this production-style runtime; run `npm run dev` separately if you need rapid iteration.

## Obtaining TLS Certificates

1. Ensure ports `80` and `443` are publicly reachable and your DNS `A/AAAA` records point at the host.
2. Issue certificates for the first time (this can run while the stack is up – the proxy serves the ACME challenge):

   ```bash
   docker compose -f deploy/docker/docker-compose.yml run --rm \
     -e DOMAINS=example.com,www.example.com \
     -e DOMAIN=example.com \
     -e SSL_EMAIL=admin@example.com \
     certbot issue
   ```

   Set `STAGING=true` for a Let’s Encrypt staging dry-run if needed.
3. The long-running `certbot` service performs renewal checks every 12 hours (`RENEW_INTERVAL_HOURS` environment variable). Certificates and ACME state persist in the named volumes `certbot-etc` and `certbot-var`.
4. After a successful issuance the proxy automatically switches from the self-signed certificate to the Let’s Encrypt certificate via symbolic links created at container start.

## Docker Images

- `deploy/docker/next.Dockerfile` builds a standalone Next.js runtime using whichever package manager lockfile is present. The runtime executes as a non-root user and exposes port `3000`.
- `deploy/docker/nginx/Dockerfile` installs Nginx with sane TLS defaults and routes traffic to the `next` service. During startup a hook in `/docker-entrypoint.d` generates or symlinks certificates so the container may boot before Let’s Encrypt issuance completes.
- `deploy/certbot/Dockerfile` wraps the official Certbot image with `renew.sh`, supporting `issue` and looping `renew` commands.

## Remote Deployment Workflow

1. Push the repository to GitHub and enable Actions.
2. Add the following repository secrets (or adapt the workflow to your deployment target):
   - `SSH_HOST`, `SSH_USER`, `SSH_KEY` – Target host connection info.
   - `REMOTE_PROJECT_PATH` – Directory on the host containing this repository/compose file.
   - `DOMAIN`, `DOMAINS`, `SSL_EMAIL` – Passed through for TLS automation.
3. Optional: set `DOMAINS` to a comma-separated list (e.g. `example.com,www.example.com`).
4. On each push to `main`, workflow steps:
   1. Install dependencies, lint, and build the Next.js project.
   2. Build multi-arch Docker images for the app and proxy, pushing to GHCR (`ghcr.io/<owner>/<repo>-next|nginx`).
   3. (Optional) SSH into the host, export the image references, and run `docker compose pull`/`up -d`. Remove or adjust the job if you deploy differently.

### Running Manually on the Host

```bash
export NEXT_IMAGE=ghcr.io/<owner>/<repo>-next:latest
export NGINX_IMAGE=ghcr.io/<owner>/<repo>-nginx:latest
export DOMAIN=example.com
export DOMAINS=example.com,www.example.com
export SSL_EMAIL=admin@example.com

docker compose -f deploy/docker/docker-compose.yml pull
docker compose -f deploy/docker/docker-compose.yml up -d
```

Certificates live in Docker volumes; back them up or mount host directories when using production infrastructure.

## Directory Reference

- `deploy/docker/docker-compose.yml` – Service definitions, shared volumes, and image overrides via `NEXT_IMAGE` / `NGINX_IMAGE`.
- `deploy/docker/env.example` – Template for values consumed by the Next.js runtime and Certbot.
- `deploy/docker/nginx/nginx.conf` – Reverse proxy configuration with ACME challenge handler and HTTP health endpoint `GET /healthz`.
- `deploy/certbot/renew.sh` – Certbot helper script; accepts `DOMAINS`, `SSL_EMAIL`, `STAGING`, `RENEW_INTERVAL_HOURS`.
- `.github/workflows/deploy.yml` – CI/CD entrypoint; adapt or extend jobs as needed.

## Troubleshooting

- Use `docker compose logs reverse-proxy -f` to inspect Nginx startup or certificate issues.
- Trigger a dry-run renewal with `docker compose run --rm -e STAGING=true certbot renew`.
- Update dependencies and rebuild images after editing `package.json` to ensure reproducible builds.
