# Server Setup Guide

This guide covers the recommended production setup for deploying the CMS Hosting application with a self-hosted GitHub Actions runner.

## Directory Structure

### Overview

```
/home/devops/
├── gh-runner/                    # GitHub Actions runner installation
│   ├── runner.env                # Runner configuration (secrets)
│   └── register-and-run.sh       # Runner bootstrap script
│
└── cms-hosting/                  # Application deployment
    ├── docker-compose.yml        # Docker Compose configuration
    ├── .env                      # Application environment (secrets)
    ├── nginx/                    # Nginx reverse proxy files
    ├── certbot/                  # SSL certificate management
    └── data/                     # Persistent application data (optional)
        ├── uploads/              # User-uploaded files (if needed)
        └── backups/              # Application backups
```

### Why This Structure?

- **Everything in `/home/devops`**: Both runner and application live in the user's home directory for maximum simplicity.
- **No sudo needed** for file operations: User already owns everything in their home directory.
- **Minimal sudo requirements**: Only needed for systemd service management (runner), not for deployments or file operations.
- **Simpler permissions**: One user owns everything, no need for a dedicated deploy user.
- **Easy backups**: Everything important is in one location.

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

# Create directories in home (no sudo needed!)
mkdir -p ~/gh-runner
mkdir -p ~/cms-hosting
chmod 755 ~/gh-runner ~/cms-hosting
```

**Note:** All directories are created in your home directory, so you naturally own them. No sudo required!

### Configure Minimal Sudo Access

The devops user needs sudo for two purposes:
1. **Systemd operations** - Managing the runner service
2. **Package management** - Installing Docker, jq, curl, and dependencies

Configure passwordless sudo for these specific commands only:

#### 1. Runner Systemd Permissions

```bash
# Create restricted sudoers file for runner systemd operations
echo "devops ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/systemd/system/gh-runner.service" | sudo tee /etc/sudoers.d/devops-runner
echo "devops ALL=(ALL) NOPASSWD: /bin/systemctl daemon-reload" | sudo tee -a /etc/sudoers.d/devops-runner
echo "devops ALL=(ALL) NOPASSWD: /bin/systemctl * gh-runner" | sudo tee -a /etc/sudoers.d/devops-runner

# Set correct permissions
sudo chmod 0440 /etc/sudoers.d/devops-runner
```

#### 2. Package Management Permissions

```bash
# Create sudoers file for package management (Docker, jq, curl installation)
sudo tee /etc/sudoers.d/devops-packages << 'EOF'
# Allow apt-get update
devops ALL=(ALL) NOPASSWD: /usr/bin/apt-get update

# Allow installing specific package combinations
devops ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y ca-certificates curl gnupg
devops ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y jq
devops ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow Docker setup commands
devops ALL=(ALL) NOPASSWD: /usr/bin/install -m 0755 -d /etc/apt/keyrings
devops ALL=(ALL) NOPASSWD: /usr/bin/gpg --dearmor
devops ALL=(ALL) NOPASSWD: /usr/sbin/usermod -aG docker *

# Allow Docker service management
devops ALL=(ALL) NOPASSWD: /bin/systemctl start docker
devops ALL=(ALL) NOPASSWD: /bin/systemctl status docker
EOF

# Set correct permissions
sudo chmod 0440 /etc/sudoers.d/devops-packages
```

#### 3. Verify Configuration

```bash
# Verify syntax is correct (IMPORTANT!)
sudo visudo -c

# Should output:
# /etc/sudoers.d/devops-runner: parsed OK
# /etc/sudoers.d/devops-packages: parsed OK

# Test permissions (as devops user)
sudo -l

# Test specific commands (should not ask for password)
sudo systemctl status gh-runner || echo "Service not yet created - this is expected"
sudo apt-get update
```

**Replace `devops`** with your actual SSH username if different.

**Security Note:** These permissions follow the principle of least privilege - only specific commands are allowed, not full root access. The devops user cannot run arbitrary sudo commands.

### 2. Configure GitHub Secrets

In your GitHub repository, go to **Settings → Secrets and variables → Actions** and add:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `SSH_HOST` | Server IP or hostname | `116.203.123.456` |
| `SSH_USER` | SSH username | `devops` or `ubuntu` |
| `SSH_KEY` | Private SSH key | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `REMOTE_RUNNER_PATH` | Runner installation path | `/home/devops/gh-runner` |
| `REMOTE_PROJECT_PATH` | Application deployment path | `/home/devops/cms-hosting` |
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

### 3. Generate SSH Key Pair (if needed)

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
- Upload runner scripts to `/home/devops/gh-runner` (or your SSH user's home)
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
4. Deploy to your server at `/home/devops/cms-hosting`

### Manual Deployment

If you need to deploy without building (reusing existing images):

1. Go to **Actions** → **CI/CD (v1)** → **Run workflow**
2. Set `deploy_only` to `true`
3. Click **Run workflow**

## File Permissions and Security

### Recommended Permissions

```bash
# Runner directory
/home/devops/gh-runner/                      devops:devops 755
/home/devops/gh-runner/runner.env            devops:devops 600  # Contains secrets!
/home/devops/gh-runner/register-and-run.sh   devops:devops 755

# Application directory
/home/devops/cms-hosting/                    devops:devops 755
/home/devops/cms-hosting/.env                devops:devops 600  # Contains secrets!
/home/devops/cms-hosting/docker-compose.yml  devops:devops 644
```

**Note:** Replace `devops` with your actual SSH username (e.g., `ubuntu`, `admin`). Everything lives in your home directory, so you naturally own it all. No permission issues!

### Security Best Practices

1. **Minimal sudo**: Only needed for systemd operations (runner service management), not for any file operations or deployments
2. **Single user ownership**: One user owns everything, simplifying permissions and reducing complexity
3. **Protect secrets**: All `.env` files should be `600` (owner read/write only)
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

## Migrating from /opt to Home Directory

If you have an existing deployment in `/opt/cms-hosting` and want to move it to `/home/devops/cms-hosting` for simpler permissions:

### Migration Steps

```bash
# 1. Stop running containers at old location
cd /opt/cms-hosting
docker compose down

# 2. Copy everything to home directory (use Docker to avoid sudo!)
docker run --rm \
  -v /opt/cms-hosting:/source:ro \
  -v /home/devops:/target \
  alpine cp -a /source /target/cms-hosting

# 3. Take ownership (no sudo needed in your home!)
chown -R devops:devops ~/cms-hosting

# 4. Test at new location
cd ~/cms-hosting
docker compose up -d

# 5. Verify everything works
docker compose ps
docker compose logs
curl http://localhost

# 6. Update GitHub secret
# Go to: Settings → Secrets → Actions
# Update: REMOTE_PROJECT_PATH=/home/devops/cms-hosting

# 7. Clean up old location (only after verification!)
# You'll need sudo or root access to remove /opt/cms-hosting
sudo rm -rf /opt/cms-hosting
sudo userdel -r deploy  # Remove deploy user if no longer needed
```

### Important Notes

- **Docker volumes** (like `certbot-etc`, `certbot-var`) are stored separately in `/var/lib/docker/volumes/` and will work automatically
- No configuration changes needed in `docker-compose.yml` - all paths are relative
- Always verify the new location works before deleting the old one
- Update your `REMOTE_PROJECT_PATH` GitHub secret to the new path

## Maintenance

### Viewing Application Logs

```bash
# SSH into server
ssh user@your-server

# View all service logs
cd ~/cms-hosting
docker compose logs -f

# View specific service
docker compose logs -f next
docker compose logs -f reverse-proxy
docker compose logs -f certbot
```

### Restarting Services

```bash
# Restart application
cd ~/cms-hosting
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
# Create backup directory
mkdir -p ~/backups

# Backup application configuration (no sudo needed!)
tar -czf ~/backups/cms-hosting-config-$(date +%Y%m%d).tar.gz \
  ~/cms-hosting/docker-compose.yml \
  ~/cms-hosting/.env \
  ~/cms-hosting/nginx \
  ~/cms-hosting/certbot

# Backup Docker volumes
docker run --rm \
  -v certbot-etc:/data \
  -v ~/backups:/backup \
  alpine tar -czf /backup/certbot-$(date +%Y%m%d).tar.gz -C /data .

# Backup application data (if using bind mounts)
tar -czf ~/backups/cms-hosting-data-$(date +%Y%m%d).tar.gz \
  ~/cms-hosting/data 2>/dev/null || echo "No data directory"
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

### Runner Setup: Sudo Password Required Error

If you get `sudo: a password is required` error when running the runner workflow:

**Cause:** Your SSH user doesn't have passwordless sudo configured for required operations.

**Solution:** Follow the "Configure Minimal Sudo Access" section in the Initial Server Setup. You need both:
1. **Runner systemd permissions** (`/etc/sudoers.d/devops-runner`)
2. **Package management permissions** (`/etc/sudoers.d/devops-packages`)

Quick check:
```bash
# Verify both files exist
sudo ls -la /etc/sudoers.d/devops-*

# Check your sudo permissions
sudo -l

# If files are missing, follow the setup instructions in "Configure Minimal Sudo Access"
```

Then re-run the workflow in GitHub Actions.

### Application Not Accessible

```bash
# Check if containers are running
cd ~/cms-hosting
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
cd ~/cms-hosting

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

If you prefer a different location than `/home/devops`, consider:

### `/opt/cms-hosting`
- **Purpose**: Standard Linux location for optional third-party software
- **Best for**: Professional/enterprise setups, multi-tenant servers
- **Pros**: Follows FHS standards, clear separation from user data
- **Cons**: Requires dedicated user or sudo for deployments

### `/srv/cms-hosting`
- **Purpose**: FHS standard for "site-specific data"
- **Best for**: Web services, HTTP-served content
- **Pros**: Semantically correct for web apps
- **Cons**: Less common in practice, similar sudo requirements as /opt

## Summary

This production setup provides:
- ✅ Everything in user's home directory for maximum simplicity
- ✅ No sudo needed for deployments or file operations
- ✅ Minimal sudo requirements (only for runner's systemd service)
- ✅ Single user owns everything - no permission complexity
- ✅ Easy to manage, backup, and scale
- ✅ Automated deployment via GitHub Actions
- ✅ Persistent data handling via Docker volumes
- ✅ SSL certificate automation

For questions or issues, check the GitHub repository or open an issue.

