# Server Setup Guide

This guide covers the recommended production setup for deploying the CMS Hosting application with a self-hosted GitHub Actions runner.

## Directory Structure

### Overview

```
/opt/
├── gh-runner/                    # GitHub Actions runner installation
│   ├── runner.env                # Runner configuration (secrets)
│   └── register-and-run.sh       # Runner bootstrap script
│
└── cms-hosting/                  # Application deployment
    ├── docker-compose.yml        # Docker Compose configuration
    ├── .env                      # Application environment (secrets)
    ├── nginx/                    # Nginx reverse proxy files
    ├── certbot/                  # SSL certificate management
    └── data/                     # Persistent application data
        ├── uploads/              # User-uploaded files (if needed)
        └── backups/              # Application backups
```

### Why This Structure?

- **`/opt/gh-runner`**: Standard Linux location for optional third-party software. The runner is a system service that needs to be isolated from user data.
- **`/opt/cms-hosting`**: Your application lives here, separate from system files and easy to manage.
- **Clear separation**: Runner (system service) vs. Application (user service) are cleanly separated.
- **Follows FHS**: Adheres to the [Filesystem Hierarchy Standard](https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard).

## Initial Server Setup

### Prerequisites

- Ubuntu 20.04+ or Debian 11+ server
- Root or sudo access
- SSH access configured
- Domain name pointing to your server

### 1. Create Directory Structure

```bash
# SSH into your server
ssh user@your-server

# Create runner directory (owned by SSH user for initial setup)
# Note: The systemd service will run as root, but the GitHub workflow
# needs to upload files as your SSH user, so we set ownership accordingly
sudo mkdir -p /opt/gh-runner
sudo chown $USER:$USER /opt/gh-runner
sudo chmod 755 /opt/gh-runner

# Create application directory with dedicated user
sudo mkdir -p /opt/cms-hosting
sudo useradd -r -s /bin/bash -d /opt/cms-hosting -m deploy
sudo chown -R deploy:deploy /opt/cms-hosting
sudo chmod 755 /opt/cms-hosting
```

**Note:** If you get a warning `useradd: warning: the home directory /opt/cms-hosting already exists`, that's normal and harmless - the directory was created in the previous step.

### 2. Add Deploy User to Docker Group

```bash
# Allow the deploy user to run Docker commands
sudo usermod -aG docker deploy

# Verify
sudo -u deploy docker ps
```

### 3. Configure GitHub Secrets

In your GitHub repository, go to **Settings → Secrets and variables → Actions** and add:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `SSH_HOST` | Server IP or hostname | `116.203.123.456` |
| `SSH_USER` | SSH username | `root` or `ubuntu` |
| `SSH_KEY` | Private SSH key | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `REMOTE_RUNNER_PATH` | Runner installation path | `/opt/gh-runner` |
| `REMOTE_PROJECT_PATH` | Application deployment path | `/opt/cms-hosting` |
| `RUNNER_REPO` | GitHub repository | `owner/repo` |
| `RUNNER_NAME` | Unique runner name | `hetzner-cms-runner` |
| `RUNNER_LABELS` | Runner labels (comma-separated) | `self-hosted,hetzner,linux,docker` |
| `RUNNER_REG_PAT` | Personal Access Token | `ghp_xxxxxxxxxxxxx` |
| `DOMAIN` | Primary domain | `example.com` |
| `DOMAINS` | All domains (comma-separated) | `example.com,www.example.com` |
| `SSL_EMAIL` | Email for Let's Encrypt | `admin@example.com` |

#### Creating the Personal Access Token (PAT)

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with these scopes:
   - `repo` (Full control of private repositories)
   - `admin:repo_hook` (Full control of repository hooks)
   - `workflow` (Update GitHub Action workflows)
3. Copy the token and save it as `RUNNER_REG_PAT` secret

### 4. Generate SSH Key Pair (if needed)

```bash
# On your local machine
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_deploy

# Copy public key to server
ssh-copy-id -i ~/.ssh/github_deploy.pub user@your-server

# Add private key to GitHub Secrets as SSH_KEY
cat ~/.ssh/github_deploy
```

## Deploying the Runner

### First-Time Setup

1. Go to your GitHub repository
2. Navigate to **Actions** → **Runner** workflow
3. Click **Run workflow**
4. Select `start` from the dropdown
5. Click **Run workflow**

This will:
- Install Docker (if not present)
- Upload runner scripts to `/opt/gh-runner`
- Create and start the `gh-runner.service` systemd service
- Register the runner with GitHub

### Verify Runner Status

Check your repository's **Settings → Actions → Runners**. You should see your runner listed with a green "Idle" status.

On the server:
```bash
# Check systemd service
sudo systemctl status gh-runner

# Check Docker container
docker ps | grep runner

# View logs
sudo journalctl -u gh-runner -f
```

## Deploying the Application

### First Deployment

After the runner is set up, trigger the main deployment:

1. Push to `main` branch, or
2. Go to **Actions** → **CI/CD (v1)** → **Run workflow**

The workflow will:
1. Run linting and build checks
2. Build Docker images (Next.js app and Nginx)
3. Push images to GitHub Container Registry (GHCR)
4. Deploy to your server at `/opt/cms-hosting`

### Manual Deployment

If you need to deploy without building (reusing existing images):

1. Go to **Actions** → **CI/CD (v1)** → **Run workflow**
2. Set `deploy_only` to `true`
3. Click **Run workflow**

## File Permissions and Security

### Recommended Permissions

```bash
# Runner directory (owned by SSH user for GitHub workflow uploads)
/opt/gh-runner/                    ssh-user:ssh-user 755

# Runner configuration (created by workflow, contains secrets!)
/opt/gh-runner/runner.env          ssh-user:ssh-user 600

# Runner script (created by workflow)
/opt/gh-runner/register-and-run.sh ssh-user:ssh-user 755

# Application directory
/opt/cms-hosting/                  deploy:deploy 755

# Application configuration (contains secrets!)
/opt/cms-hosting/.env              deploy:deploy 600

# Docker Compose file
/opt/cms-hosting/docker-compose.yml deploy:deploy 644
```

**Note:** Replace `ssh-user` with your actual SSH username (e.g., `ubuntu`, `devops`, `root`). The runner systemd service will run as root, but the directory needs to be writable by your SSH user for the GitHub workflow to upload files.

### Security Best Practices

1. **Separate concerns**: Runner systemd service runs as root; runner files owned by SSH user for uploads; application runs as `deploy` user
2. **Protect secrets**: All `.env` files should be `600` (owner read/write only)
3. **Docker socket**: The runner has access to Docker socket for building images
4. **Firewall**: Configure UFW or iptables to only allow ports 22 (SSH), 80 (HTTP), 443 (HTTPS)
5. **SSH hardening**: 
   - Disable password authentication
   - Use key-based authentication only
   - Consider changing SSH port from default 22

### Example UFW Setup

```bash
# Enable UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH, HTTP, HTTPS
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status verbose
```

## Migrating from Existing Installation

If you have an existing deployment in a different location (e.g., `/home/devops/cms-hosting`), you can migrate to `/opt/cms-hosting`:

### Migration Steps

```bash
# 1. Stop running containers at old location
cd /home/devops/cms-hosting  # or your current path
docker compose down

# 2. Copy everything to new location
sudo cp -a /home/devops/cms-hosting/. /opt/cms-hosting/

# 3. Fix ownership
sudo chown -R deploy:deploy /opt/cms-hosting

# 4. Test at new location
cd /opt/cms-hosting
docker compose up -d

# 5. Verify everything works
docker compose ps
docker compose logs
curl http://localhost

# 6. Update GitHub secret
# Go to: Settings → Secrets → Actions
# Update: REMOTE_PROJECT_PATH=/opt/cms-hosting

# 7. Clean up old location (only after verification!)
sudo rm -rf /home/devops/cms-hosting
```

### Important Notes

- **Docker volumes** (like `certbot-etc`, `certbot-var`) are stored separately in `/var/lib/docker/volumes/` and will work automatically
- The `-a` flag in `cp` preserves permissions, timestamps, and directory structure
- Always verify the new location works before deleting the old one
- Update your `REMOTE_PROJECT_PATH` GitHub secret to the new path

## Maintenance

### Viewing Application Logs

```bash
# SSH into server
ssh user@your-server

# View all service logs
cd /opt/cms-hosting
docker compose logs -f

# View specific service
docker compose logs -f next
docker compose logs -f reverse-proxy
docker compose logs -f certbot
```

### Restarting Services

```bash
# Restart application
cd /opt/cms-hosting
docker compose restart

# Restart specific service
docker compose restart next

# Restart runner
sudo systemctl restart gh-runner
```

### Updating Application

Push changes to `main` branch or manually trigger the workflow. The deployment will:
1. Pull new images
2. Stop old containers
3. Start new containers
4. Keep volumes intact (data persists)

### Backup Strategy

```bash
# Backup application configuration
sudo tar -czf /opt/backups/cms-hosting-config-$(date +%Y%m%d).tar.gz \
  /opt/cms-hosting/docker-compose.yml \
  /opt/cms-hosting/.env \
  /opt/cms-hosting/nginx \
  /opt/cms-hosting/certbot

# Backup Docker volumes
docker run --rm \
  -v certbot-etc:/data \
  -v /opt/backups:/backup \
  alpine tar -czf /backup/certbot-$(date +%Y%m%d).tar.gz -C /data .

# Backup application data (if using bind mounts)
sudo tar -czf /opt/backups/cms-hosting-data-$(date +%Y%m%d).tar.gz \
  /opt/cms-hosting/data
```

### Monitoring

```bash
# Check container health
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Check disk usage
df -h
docker system df

# Check Docker logs for errors
docker compose logs --tail=100 | grep -i error

# Check SSL certificate expiry
docker compose exec reverse-proxy openssl x509 -in /etc/nginx/tls/server.crt -noout -dates
```

## Troubleshooting

### Runner Not Appearing in GitHub

```bash
# Check service status
sudo systemctl status gh-runner

# Check logs
sudo journalctl -u gh-runner -n 50

# Restart service
sudo systemctl restart gh-runner

# Check Docker container
docker ps -a | grep runner
```

### Runner Setup: Permission Denied Error

If you get `Permission denied` or `Cannot mkdir` errors when running the runner workflow:

```bash
# On your server, fix permissions for the runner directory
sudo chown -R $USER:$USER /opt/gh-runner
sudo chmod 755 /opt/gh-runner

# Verify ownership matches your SSH user
ls -ld /opt/gh-runner
# Should show: drwxr-xr-x ... your-ssh-user your-ssh-user ... /opt/gh-runner
```

**Cause:** The GitHub workflow uploads files via SCP as your SSH user. If `/opt/gh-runner` is owned by `root`, the upload will fail.

**Solution:** The directory should be owned by your SSH user (the value in your `SSH_USER` secret). The systemd service will still run as root, which is correct.

Then re-run the workflow in GitHub Actions.

### Application Not Accessible

```bash
# Check if containers are running
cd /opt/cms-hosting
docker compose ps

# Check Nginx logs
docker compose logs reverse-proxy

# Check application logs
docker compose logs next

# Verify ports are open
sudo netstat -tlnp | grep -E '(80|443)'
```

### SSL Certificate Issues

```bash
# Check certificate status
docker compose logs certbot

# Manually request certificate
docker compose exec certbot certbot certonly \
  --webroot -w /var/www/certbot \
  -d example.com \
  --email admin@example.com \
  --agree-tos \
  --non-interactive

# Reload Nginx
docker compose exec reverse-proxy nginx -s reload
```

### Disk Space Issues

```bash
# Clean up unused Docker resources
docker system prune -a --volumes

# Remove old images
docker image prune -a

# Check what's using space
docker system df -v
```

## Rollback Procedure

If a deployment fails:

```bash
# SSH into server
ssh user@your-server
cd /opt/cms-hosting

# Pull previous image version
docker pull ghcr.io/your-org/cms-hosting-next:PREVIOUS_SHA

# Update .env to use previous image
nano .env
# Change NEXT_IMAGE=ghcr.io/your-org/cms-hosting-next:PREVIOUS_SHA

# Restart
docker compose down
docker compose up -d
```

## Alternative Locations (Reference)

If `/opt/` doesn't suit your setup, consider:

### `/srv/cms-hosting`
- **Purpose**: FHS standard for "site-specific data"
- **Best for**: Web services, HTTP-served content
- **Pros**: Semantically correct for web apps
- **Cons**: Less common in practice

### `/home/deploy/cms-hosting`
- **Purpose**: User-based deployment
- **Best for**: Single-user servers, simpler setups
- **Pros**: Easy permissions, no sudo needed
- **Cons**: Mixes deployment with user home directory

## Summary

This production setup provides:
- ✅ Professional directory structure following Linux standards
- ✅ Clear separation between runner and application
- ✅ Proper security boundaries and permissions
- ✅ Easy to manage, backup, and scale
- ✅ Automated deployment via GitHub Actions
- ✅ Persistent data handling
- ✅ SSL certificate automation

For questions or issues, check the GitHub repository or open an issue.

