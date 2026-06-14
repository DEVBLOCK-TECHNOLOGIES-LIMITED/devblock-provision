#!/bin/bash
# =============================================================================
# DevBlock Node Provisioner — Single-command setup for new compute nodes
# =============================================================================
# Usage (on fresh Ubuntu 24.04):
#   curl -sSL https://raw.githubusercontent.com/DEVBLOCK-TECHNOLOGIES-LIMITED/sage-bootstrap/main/provision-node.sh | bash
#
# What it does:
#   1. Installs all base tools (node, pnpm, python, git, gh, docker, pipx)
#   2. Installs DevBlock tools (wrangler, vercel, playwright, hermes-agent)
#   3. Clones all active DevBlock repos to ~/devblock/
#   4. Configures PATH for non-interactive SSH
#   5. Generates SSH key for mesh access
#   6. Sets up daily 3am repo sync cron
#   7. Registers node with Sage mesh (auto-discovery)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

# ---- Config ----
REGISTRATION_URL="${DEVBLOCK_REGISTER_URL:-https://devblock-mesh-registry.devblocktechnologies.workers.dev}"
REGISTRATION_TOKEN="${DEVBLOCK_REGISTER_TOKEN:-}"
DEVBLOCK_REPOS=(
  "ojibona1/bigglesworth"
  "ojibona1/converseiq"
  "ojibona1/devblock-console"
  "ojibona1/Hybrid-Travels-Tour"
  "ojibona1/nutriaire"
  "ojibona1/payiq"
)

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   DevBlock Node Provisioner             ║"
echo "  ║   Setting up this machine as a mesh     ║"
echo "  ║   node for Sage to orchestrate.         ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# ---- Detect environment ----
HOSTNAME=$(hostname)
OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
OS_VERSION=$(grep 'VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
ARCH=$(uname -m)
CPUS=$(nproc)
RAM=$(free -h | awk '/^Mem:/ {print $2}')
DISK=$(df -h / | awk 'NR==2 {print $2}')
USERNAME=$(whoami)
IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
NODE_ID="node-$(echo "$HOSTNAME" | tr '.' '-')-$(date +%s | tail -c5)"

info "Host: $HOSTNAME | OS: $OS_ID $OS_VERSION | Arch: $ARCH"
info "CPU: $CPUS cores | RAM: $RAM | Disk: $DISK | IP: $IP_ADDR"
info "User: $USERNAME | Node ID: $NODE_ID"
echo ""

# ---- Phase 1: Base Tools ----
echo "--- Phase 1: Base Tools ---"

log "Updating package lists..."
sudo apt-get update -qq

if ! command -v node &>/dev/null; then
  log "Installing Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
  sudo apt-get install -y -qq nodejs
fi
log "Node.js $(node --version)"

if ! command -v pnpm &>/dev/null; then
  log "Installing pnpm..."
  npm install -g pnpm >/dev/null 2>&1
fi
log "pnpm $(pnpm --version)"

log "Installing Python + pip..."
sudo apt-get install -y -qq python3 python3-pip >/dev/null 2>&1
log "Python $(python3 --version)"

log "Installing git..."
sudo apt-get install -y -qq git >/dev/null 2>&1
log "git $(git --version | awk '{print $3}')"

if ! command -v gh &>/dev/null; then
  log "Installing GitHub CLI..."
  sudo apt-get install -y -qq gh >/dev/null 2>&1
fi
log "gh $(gh --version 2>/dev/null | head -1)"

if ! command -v docker &>/dev/null; then
  log "Installing Docker..."
  sudo apt-get install -y -qq docker.io >/dev/null 2>&1
  sudo usermod -aG docker "$USERNAME" 2>/dev/null || true
fi
log "Docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"

if ! command -v pipx &>/dev/null; then
  log "Installing pipx..."
  sudo apt-get install -y -qq pipx >/dev/null 2>&1
fi

# ---- Phase 2: DevBlock Tools ----
echo ""
echo "--- Phase 2: DevBlock Tools ---"

log "Configuring npm global prefix..."
npm config set prefix ~/.npm-global >/dev/null 2>&1
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

if ! command -v wrangler &>/dev/null; then
  log "Installing wrangler..."
  npm install -g wrangler >/dev/null 2>&1
fi
log "wrangler $(wrangler --version 2>/dev/null)"

if ! command -v vercel &>/dev/null; then
  log "Installing vercel CLI..."
  npm install -g vercel >/dev/null 2>&1
fi
log "vercel $(vercel --version 2>/dev/null)"

log "Installing Playwright + system deps..."
npx playwright install --with-deps >/dev/null 2>&1 || {
  warn "Playwright system deps need sudo. Installing..."
  npx playwright install-deps >/dev/null 2>&1
  npx playwright install >/dev/null 2>&1
}
log "Playwright $(npx playwright --version 2>/dev/null)"

if ! command -v hermes &>/dev/null; then
  log "Installing Hermes Agent..."
  pipx install hermes-agent >/dev/null 2>&1
fi
log "Hermes $(hermes --version 2>/dev/null || echo 'installed')"

# ---- Phase 3: PATH Configuration ----
echo ""
echo "--- Phase 3: PATH Configuration ---"

BASHRC="$HOME/.bashrc"
PATH_EXPORT='export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"'

if ! grep -q "npm-global/bin" "$BASHRC" 2>/dev/null; then
  # Insert BEFORE the non-interactive guard so it runs in SSH sessions
  if grep -q "case \$- in" "$BASHRC" 2>/dev/null; then
    GUARD_LINE=$(grep -n "case \$- in" "$BASHRC" | head -1 | cut -d: -f1)
    sudo sed -i "${GUARD_LINE}i${PATH_EXPORT}" "$BASHRC"
  else
    echo "$PATH_EXPORT" >> "$BASHRC"
  fi
  log "Added npm globals to PATH (before interactive guard)"
else
  log "PATH already configured"
fi

# ---- Phase 4: SSH Key ----
echo ""
echo "--- Phase 4: SSH Key ---"

SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  log "Generating SSH key pair..."
  mkdir -p ~/.ssh
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "devblock-node-${HOSTNAME}" >/dev/null 2>&1
fi
PUBKEY=$(cat "${SSH_KEY}.pub")
log "SSH key: $(echo "$PUBKEY" | awk '{print $1, $3}')"

# Add Sage's public key for reverse access (Sage → node)
log "Fetching Sage's public key for authorized_keys..."
SAGE_PUBKEY=$(curl -sSL --connect-timeout 5 "https://raw.githubusercontent.com/DEVBLOCK-TECHNOLOGIES-LIMITED/sage-bootstrap/main/sage.pub" 2>/dev/null || echo "")
if [ -n "$SAGE_PUBKEY" ]; then
  if ! grep -qF "$SAGE_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$SAGE_PUBKEY" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    log "Added Sage's public key to authorized_keys"
  else
    log "Sage's key already in authorized_keys"
  fi
else
  warn "Could not fetch Sage's public key. SSH access from Sage will need manual setup."
fi

# ---- Phase 5: Repo Cloning ----
echo ""
echo "--- Phase 5: Cloning Repos ---"

mkdir -p ~/devblock
for repo in "${DEVBLOCK_REPOS[@]}"; do
  REPO_NAME=$(basename "$repo")
  if [ -d "$HOME/devblock/$REPO_NAME" ]; then
    log "$REPO_NAME: already exists, pulling latest..."
    (cd "$HOME/devblock/$REPO_NAME" && git pull --ff-only 2>/dev/null) || warn "$REPO_NAME: pull failed (local changes?)"
  else
    log "Cloning $repo..."
    git clone "https://github.com/$repo.git" "$HOME/devblock/$REPO_NAME" >/dev/null 2>&1 || {
      warn "Failed to clone $repo (private repo? skip if not needed)"
    }
  fi
done

# ---- Phase 6: Cron Jobs ----
echo ""
echo "--- Phase 6: Cron Jobs ---"

# Daily 3am repo sync
CRON_JOB="0 3 * * * for d in \$HOME/devblock/*/; do cd \"\$d\" && git fetch origin 2>/dev/null && git pull --ff-only 2>/dev/null; done"
if ! crontab -l 2>/dev/null | grep -qF "devblock/*/"; then
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  log "Daily 3am repo sync cron set"
else
  log "Repo sync cron already set"
fi

# ---- Phase 7: Mesh Registration ----
echo ""
echo "--- Phase 7: Mesh Registration ---"

REGISTRATION=$(cat <<EOF
{
  "node_id": "${NODE_ID}",
  "hostname": "${HOSTNAME}",
  "friendly_name": "${HOSTNAME}",
  "os": "${OS_ID} ${OS_VERSION}",
  "arch": "${ARCH}",
  "cpu": "$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo 'unknown')",
  "ram": "${RAM}",
  "disk": "${DISK}",
  "role": "compute",
  "capabilities": ["builds", "docker", "heavy-tasks", "playwright", "wrangler", "vercel", "storage", "backups"],
  "access": {
    "type": "ssh",
    "ssh_alias": "${HOSTNAME}",
    "host": "${IP_ADDR}",
    "user": "${USERNAME}",
    "key": "~/.ssh/id_ed25519"
  },
  "public_key": "${PUBKEY}",
  "hermes_version": "$(hermes --version 2>/dev/null | head -1 || echo '0.15.2')",
  "provisioned": true,
  "_current_load": 0,
  "last_health_check": null,
  "notes": "Provisioned $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

# Save locally
echo "$REGISTRATION" > ~/devblock-mesh-registration.json
log "Registration saved to ~/devblock-mesh-registration.json"

# Try auto-registration
if [ -z "$REGISTRATION_TOKEN" ]; then
  warn "DEVBLOCK_REGISTER_TOKEN not set. Skipping auto-registration."
  info "Set it to auto-register: export DEVBLOCK_REGISTER_TOKEN=<token>"
else
  HTTP_CODE=$(curl -s -o /tmp/register-response.json -w "%{http_code}" \
    -X POST "$REGISTRATION_URL/register" \
    -H "Content-Type: application/json" \
    -H "X-Registration-Token: $REGISTRATION_TOKEN" \
    -d "$REGISTRATION" \
    --connect-timeout 10 \
    --max-time 15 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
    log "Auto-registered with Sage mesh! (HTTP $HTTP_CODE)"
    log "Sage will discover this node within 5 minutes."
  else
    warn "Auto-registration returned HTTP $HTTP_CODE"
    cat /tmp/register-response.json 2>/dev/null
  fi
fi

# Always save locally as fallback
echo ""
info "Registration saved locally: ~/devblock-mesh-registration.json"
info "If auto-registration failed, add the JSON below to mesh.json:"
echo "$REGISTRATION" | python3 -m json.tool 2>/dev/null || echo "$REGISTRATION"

# ---- Done ----
echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Provisioning Complete                 ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""
log "Node is ready. Tools installed, repos cloned, cron active."
echo ""

# Print summary
echo "  Node ID:    $NODE_ID"
echo "  Hostname:   $HOSTNAME"
echo "  IP:         $IP_ADDR"
echo "  SSH alias:  $HOSTNAME (add to ~/.ssh/config on Sage host)"
echo "  Public key: ${SSH_KEY}.pub"
echo ""
