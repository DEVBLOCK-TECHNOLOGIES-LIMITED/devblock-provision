#!/bin/bash
# =============================================================================
# DevBlock Node Provisioner — Plug this machine into the Sage mesh
# =============================================================================
# Works on: Ubuntu, Debian, macOS. Add more: see pkg_install().
# Usage:
#   curl -sSL https://raw.githubusercontent.com/DEVBLOCK-TECHNOLOGIES-LIMITED/devblock-provision/main/provision-node.sh | DEVBLOCK_REGISTER_TOKEN=*** bash
# =============================================================================
set -euo pipefail

# ── Palette ──────────────────────────────────────────────────────────────────
C_BOLD='\033[1m'; C_DIM='\033[2m'; C_RESET='\033[0m'
C_WHITE='\033[37m'; C_GREEN='\033[32m'; C_BLUE='\033[34m'
C_YELLOW='\033[33m'; C_RED='\033[31m'; C_CYAN='\033[36m'
OK="${C_GREEN}✓${C_RESET}"; FAIL="${C_RED}✗${C_RESET}"
WARN="${C_YELLOW}▲${C_RESET}"
PHASE_TOTAL=5; PHASE_CURRENT=0
START_TIME=$(date +%s)

step() {
  PHASE_CURRENT=$((PHASE_CURRENT + 1))
  printf "\n  ${C_BOLD}${C_WHITE}[%d/%d]${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$PHASE_CURRENT" "$PHASE_TOTAL" "$1"
  printf "  ${C_DIM}──────────────────────────────────────────${C_RESET}\n"
}
done_ok()   { printf "  ${OK} ${C_GREEN}%s${C_RESET}\n" "$1"; }
done_sub()  { printf "    ${C_DIM}${OK} %s${C_RESET}\n" "$1"; }
running()   { printf "  ${C_CYAN}⚡${C_RESET} %s" "$1"; }
elapsed()   { printf " ${C_DIM}(%ss)${C_RESET}\n" "$(($(date +%s) - $2))"; }
have()      { command -v "$1" &>/dev/null; }

# ── Config ───────────────────────────────────────────────────────────────────
REGISTRATION_URL="${DEVBLOCK_REGISTER_URL:-https://devblock-mesh-registry.devblocktechnologies.workers.dev}"
REG_TOK_ENV="DEVBLOCK_REGISTER_TOKEN"
REGISTRATION_TOKEN="${DEVBLOCK_REGISTER_TOKEN:-}"

# ── OS Detection ─────────────────────────────────────────────────────────────
UNAME_S=$(uname -s)
case "$UNAME_S" in
  Darwin)
    OS="macos"; OS_ID="macOS"; OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    PKG_MGR="brew"; SHELL_RC="$HOME/.zshrc"
    ;;
  Linux)
    OS="linux"
    OS_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "linux")
    OS_VERSION=$(grep 'VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    SHELL_RC="$HOME/.bashrc"
    if have apt-get; then PKG_MGR="apt"
    elif have dnf; then PKG_MGR="dnf"
    elif have pacman; then PKG_MGR="pacman"
    elif have apk; then PKG_MGR="apk"
    else PKG_MGR="none"; fi
    ;;
  *)
    OS="unknown"; OS_ID="$UNAME_S"; OS_VERSION="unknown"
    PKG_MGR="none"; SHELL_RC="$HOME/.profile"
    ;;
esac
ARCH=$(uname -m)

# ── Detect Environment ───────────────────────────────────────────────────────
HOSTNAME=$(hostname)
if [ "$OS" = "macos" ]; then
  CPUS=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
  RAM=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0fGB", $1/1024/1024/1024}' || echo "unknown")
  DISK=$(df -h / | awk 'NR==2 {print $2}')
  IP_ADDR=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1 || echo "unknown")
  CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown")
else
  CPUS=$(nproc 2>/dev/null || echo 1)
  RAM=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "unknown")
  DISK=$(df -h / | awk 'NR==2 {print $2}')
  IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
  CPU_MODEL=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "unknown")
fi
USERNAME=$(whoami)
NODE_ID="node-$(echo "$HOSTNAME" | tr '.' '-')-$(date +%s | tail -c5)"

# ── Package Manager Abstraction ──────────────────────────────────────────────
pkg_update() {
  case "$PKG_MGR" in
    brew) brew update >/dev/null 2>&1 || true ;;
    apt)  sudo apt-get update -qq 2>/dev/null || true ;;
    dnf)  sudo dnf check-update -q 2>/dev/null || true ;;
    *)    true ;;
  esac
}
pkg_install() {
  local pkg="$1"
  case "$PKG_MGR" in
    brew) have "$pkg" || brew install "$pkg" >/dev/null 2>&1 ;;
    apt)  have "$pkg" || sudo apt-get install -y -qq "$pkg" >/dev/null 2>&1 ;;
    dnf)  have "$pkg" || sudo dnf install -y -q "$pkg" >/dev/null 2>&1 ;;
    *)    true ;;
  esac
}
install_npm_global() { npm install -g "$1" >/dev/null 2>&1; }

# ── Header ───────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
printf "${C_BOLD}${C_WHITE}"
printf "\n  ╭────────────────────────────────────────────╮\n"
printf "  │                                            │\n"
printf "  │   %-38s  │\n" "DevBlock Node Provisioner"
printf "  │   %-38s  │\n" "Connect this machine to the Sage mesh"
printf "  │                                            │\n"
printf "  ╰────────────────────────────────────────────╯\n"
printf "${C_RESET}\n"

printf "  ${C_DIM}%s${C_RESET}  ${C_BOLD}%s${C_RESET}\n" "host" "$HOSTNAME"
printf "  ${C_DIM}%s${C_RESET}  %s %s • %s • %s cores • %s RAM • %s disk\n" \
  "spec" "$OS_ID" "$OS_VERSION" "$ARCH" "$CPUS" "$RAM" "$DISK"
printf "  ${C_DIM}%s${C_RESET}  %s@%s${C_RESET}\n" "net" "$USERNAME" "$IP_ADDR"
printf "  ${C_DIM}%s${C_RESET}  %s${C_RESET}\n" "id" "$NODE_ID"
if [ "$PKG_MGR" = "none" ]; then
  printf "  ${WARN} ${C_YELLOW}No package manager detected — manual install needed${C_RESET}\n"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 1/5: Base Tools
# ═══════════════════════════════════════════════════════════════════════════════
step "System Tools"
T0=$(date +%s)

running "updating package index..."
pkg_update
elapsed 1 "$T0"
done_ok "Package index current"

T0=$(date +%s)

# Node.js
if [ "$OS" = "linux" ] && ! have node; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
  sudo apt-get install -y -qq nodejs >/dev/null 2>&1
elif [ "$OS" = "macos" ] && ! have node; then
  pkg_install node
fi
done_sub "node $(node --version 2>/dev/null || echo 'checking...')"

have pnpm || install_npm_global pnpm
done_sub "pnpm $(pnpm --version 2>/dev/null)"

# Python
case "$OS" in
  macos) pkg_install python3 ;;
  linux) sudo apt-get install -y -qq python3 python3-pip >/dev/null 2>&1 || true ;;
esac
done_sub "python $(python3 --version 2>/dev/null | awk '{print $2}')"

pkg_install git
done_sub "git $(git --version 2>/dev/null | awk '{print $3}')"

pkg_install gh
done_sub "gh $(gh --version 2>/dev/null | head -1 | awk '{print $3}')"

# Docker
if [ "$OS" = "linux" ]; then
  if ! have docker; then
    sudo apt-get install -y -qq docker.io >/dev/null 2>&1
    sudo usermod -aG docker "$USERNAME" 2>/dev/null || true
  fi
  done_sub "docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
elif [ "$OS" = "macos" ]; then
  if have docker; then
    done_sub "docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
  else
    printf "    ${WARN} ${C_YELLOW}Docker not found — install Docker Desktop manually${C_RESET}\n"
  fi
fi

# pipx
case "$OS" in
  macos) pkg_install pipx; pipx ensurepath >/dev/null 2>&1 || true ;;
  linux) pkg_install pipx ;;
esac
done_sub "pipx ready"

elapsed 1 "$T0"

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 2/5: DevBlock Toolchain
# ═══════════════════════════════════════════════════════════════════════════════
step "DevBlock Toolchain"
T0=$(date +%s)

npm config set prefix ~/.npm-global >/dev/null 2>&1
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
# Also add pipx path on macOS
if [ "$OS" = "macos" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

have wrangler || install_npm_global wrangler
done_sub "wrangler $(wrangler --version 2>/dev/null)"

have vercel || install_npm_global vercel
done_sub "vercel $(vercel --version 2>/dev/null)"

running "playwright (browsers + deps)..."
if [ "$OS" = "linux" ]; then
  npx playwright install --with-deps >/dev/null 2>&1 || {
    npx playwright install-deps >/dev/null 2>&1
    npx playwright install >/dev/null 2>&1
  }
else
  npx playwright install >/dev/null 2>&1
fi
printf " ${OK}\n"
done_sub "playwright $(npx playwright --version 2>/dev/null)"

have hermes || pipx install hermes-agent >/dev/null 2>&1
done_sub "hermes $(hermes --version 2>/dev/null | head -1 || echo 'installed')"

elapsed 1 "$T0"

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 3/5: System Configuration
# ═══════════════════════════════════════════════════════════════════════════════
step "System Configuration"
T0=$(date +%s)

PATH_EXPORT='export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"'

if ! grep -q "npm-global/bin" "$SHELL_RC" 2>/dev/null; then
  if grep -q "case \$- in" "$SHELL_RC" 2>/dev/null; then
    GUARD_LINE=$(grep -n "case \$- in" "$SHELL_RC" | head -1 | cut -d: -f1)
    sed -i '' "${GUARD_LINE}i\\" "$SHELL_RC" 2>/dev/null || true
    sed -i "${GUARD_LINE}i${PATH_EXPORT}" "$SHELL_RC" 2>/dev/null || true
  else
    echo "$PATH_EXPORT" >> "$SHELL_RC"
  fi
  done_sub "PATH configured in $(basename $SHELL_RC)"
else
  done_sub "PATH already configured"
fi

# SSH key
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  mkdir -p ~/.ssh
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "devblock-node-${HOSTNAME}" >/dev/null 2>&1
  done_sub "SSH key generated"
else
  done_sub "SSH key exists"
fi
PUBKEY=$(cat "${SSH_KEY}.pub")
FINGERPRINT=$(echo "$PUBKEY" | awk '{print $1, $3}')

# Sage's public key
SAGE_PUBKEY=$(curl -sSL --connect-timeout 5 "https://raw.githubusercontent.com/DEVBLOCK-TECHNOLOGIES-LIMITED/devblock-provision/main/sage.pub" 2>/dev/null || echo "")
if [ -n "$SAGE_PUBKEY" ]; then
  if ! grep -qF "$SAGE_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$SAGE_PUBKEY" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    done_sub "Sage key → authorized_keys"
  else
    done_sub "Sage key already authorized"
  fi
else
  printf "  ${WARN} ${C_YELLOW}Could not fetch Sage public key${C_RESET}\n"
fi

elapsed 1 "$T0"

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 4/5: Mesh Registration
# ═══════════════════════════════════════════════════════════════════════════════
step "Mesh Registration"
T0=$(date +%s)

# Cross-platform capabilities
if [ "$OS" = "macos" ]; then
  CAPABILITIES='["builds", "playwright", "wrangler", "vercel", "heavy-tasks"]'
  ROLE="compute"
else
  CAPABILITIES='["builds", "docker", "heavy-tasks", "playwright", "wrangler", "vercel", "storage", "backups"]'
  ROLE="compute"
fi

REGISTRATION=$(cat <<JSONEOF
{
  "node_id": "${NODE_ID}",
  "hostname": "${HOSTNAME}",
  "friendly_name": "${HOSTNAME}",
  "os": "${OS_ID} ${OS_VERSION}",
  "arch": "${ARCH}",
  "cpu": "${CPU_MODEL}",
  "ram": "${RAM}",
  "disk": "${DISK}",
  "role": "${ROLE}",
  "capabilities": ${CAPABILITIES},
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
  "notes": "Provisioned $(date -u +%Y-%m-%dT%H:%M:%SZ) on ${OS}"
}
JSONEOF
)

echo "$REGISTRATION" > ~/devblock-mesh-registration.json

if [ -z "$REGISTRATION_TOKEN" ]; then
  printf "  ${WARN} ${C_YELLOW}No registration token — saved locally${C_RESET}\n"
  printf "  ${C_DIM}  Add ~/devblock-mesh-registration.json to mesh.json${C_RESET}\n"
else
  running "registering with Sage mesh..."
  HTTP_CODE=$(curl -s -o /tmp/mr.json -w "%{http_code}" \
    -X POST "$REGISTRATION_URL/register" \
    -H "Content-Type: application/json" \
    -H "X-Registration-Token: $REGISTRATION_TOKEN" \
    -d "$REGISTRATION" \
    --connect-timeout 10 --max-time 15 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
    printf " ${OK}\n"
    done_ok "Registered with Sage mesh"
    printf "  ${C_DIM}  Sage discovers this node within 5 minutes${C_RESET}\n"
  else
    printf " ${FAIL}\n"
    printf "  ${WARN} ${C_YELLOW}Registration returned HTTP %s${C_RESET}\n" "$HTTP_CODE"
    cat /tmp/mr.json 2>/dev/null | head -3
  fi
fi

elapsed 1 "$T0"

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 5/5: Verification
# ═══════════════════════════════════════════════════════════════════════════════
step "Verification"
T0=$(date +%s)

FAILS=0
check() {
  if have "$1"; then
    done_sub "$1 $(command -v "$1" 2>/dev/null)"
  else
    printf "    ${FAIL} ${C_RED}%s missing${C_RESET}\n" "$1"
    FAILS=$((FAILS + 1))
  fi
}

check node; check pnpm; check python3; check git; check gh
if [ "$OS" = "linux" ]; then check docker; fi
check wrangler; check vercel; check hermes

if [ -f "$SSH_KEY" ]; then
  done_sub "ssh key ready"
else
  printf "    ${FAIL} ${C_RED}ssh key missing${C_RESET}\n"; FAILS=$((FAILS + 1))
fi

TOTAL_TOOLS=9
[ "$OS" = "macos" ] && TOTAL_TOOLS=8
if [ "$FAILS" -eq 0 ]; then
  printf "\n  ${OK} ${C_GREEN}All %d tools verified${C_RESET}\n" "$TOTAL_TOOLS"
else
  printf "\n  ${WARN} ${C_YELLOW}%d of %d tool(s) missing${C_RESET}\n" "$FAILS" "$TOTAL_TOOLS"
fi

elapsed 1 "$T0"

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL_TIME=$(($(date +%s) - START_TIME))
printf "\n${C_BOLD}${C_WHITE}"
printf "  ╭────────────────────────────────────────────╮\n"
printf "  │                                            │\n"
if [ -n "$REGISTRATION_TOKEN" ]; then
  printf "  │   ${C_GREEN}✓  Node provisioned & registered${C_WHITE}         │\n"
else
  printf "  │   ${C_YELLOW}▲  Node provisioned (manual registration)${C_WHITE} │\n"
fi
printf "  │                                            │\n"
printf "  │   ${C_DIM}os${C_WHITE}     %-33s │\n" "$OS_ID $OS_VERSION"
printf "  │   ${C_DIM}node${C_WHITE}   %-33s │\n" "$NODE_ID"
printf "  │   ${C_DIM}ssh${C_WHITE}    %-33s │\n" "$USERNAME@$IP_ADDR"
printf "  │   ${C_DIM}time${C_WHITE}   %-33s │\n" "${TOTAL_TIME}s"
printf "  │                                            │\n"
printf "  ╰────────────────────────────────────────────╯\n${C_RESET}\n"

printf "  ${C_DIM}Public key:${C_RESET} ${FINGERPRINT}\n"
printf "  ${C_DIM}Saved to:${C_RESET}   ~/devblock-mesh-registration.json\n"
echo ""
