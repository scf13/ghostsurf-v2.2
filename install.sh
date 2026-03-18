#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║           GhostSurf v2.2 — Installer                         ║
# ╚═══════════════════════════════════════════════════════════════╝

set -uo pipefail
[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash install.sh"; exit 1; }

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2m'; NC='\033[0m'
ok()   { echo -e "  ${G}[✔]${NC} $*"; }
fail() { echo -e "  ${R}[✘]${NC} $*" >&2; }
warn() { echo -e "  ${Y}[!]${NC} $*"; }
step() { echo -e "\n  ${W}$*${NC}"; echo -e "${D}  ─────────────────────────────────────────────────${NC}"; }

_restore() {
    echo -e "\n  ${R}[!] Install failed — restoring network...${NC}"
    iptables -F; iptables -t nat -F
    iptables -P INPUT ACCEPT; iptables -P OUTPUT ACCEPT
    ip6tables -F; ip6tables -P OUTPUT ACCEPT
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    systemctl restart systemd-resolved 2>/dev/null || true
    echo -e "  ${G}[✔] Network restored.${NC}\n"
}
trap '_restore' ERR SIGINT SIGTERM

echo ""
echo -e "${C}  ╔════════════════════════════════════════════╗${NC}"
echo -e "${C}  ║     GhostSurf v2.2 — Installing...        ║${NC}"
echo -e "${C}  ╚════════════════════════════════════════════╝${NC}"
echo ""

step "Step 1 — Restore network before install"
iptables -F 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true
ok "iptables cleared"

if ! getent hosts google.com &>/dev/null; then
    warn "DNS broken — fixing..."
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    systemctl restart NetworkManager 2>/dev/null || true
    sleep 3
fi
ping -c 1 -W 4 1.1.1.1 &>/dev/null && ok "Internet: OK" || { fail "No internet"; exit 1; }

step "Step 2 — Install dependencies"
apt-get update -qq 2>/dev/null && ok "Package lists updated" || warn "apt update issues"
for pkg in tor torsocks iptables curl wget dnsutils netcat-traditional yad xterm; do
    dpkg -s "$pkg" &>/dev/null 2>&1 && ok "$pkg (already installed)" && continue
    apt-get install -y -qq "$pkg" 2>/dev/null && ok "$pkg" || warn "$pkg failed (non-critical)"
done

id debian-tor &>/dev/null 2>&1 || \
    useradd -r -s /usr/sbin/nologin debian-tor 2>/dev/null && ok "debian-tor user OK"

step "Step 3 — Install GhostSurf v2.2"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Validate required files
for f in ghostsurf.sh ghostsurf-gui.sh ghostsurf-auto.sh lib/utils.sh lib/rules.sh lib/verify.sh; do
    [[ -f "$SCRIPT_DIR/$f" ]] && ok "$f found" || { fail "$f MISSING"; exit 1; }
done

# Install lib/ to a shared location
mkdir -p /usr/local/lib/ghostsurf
cp "$SCRIPT_DIR/lib/"*.sh /usr/local/lib/ghostsurf/
chmod 644 /usr/local/lib/ghostsurf/*.sh
ok "lib/ → /usr/local/lib/ghostsurf/"

# Install CLI
cp "$SCRIPT_DIR/ghostsurf.sh" /usr/local/bin/ghostsurf
chmod 750 /usr/local/bin/ghostsurf
ok "ghostsurf → /usr/local/bin/ghostsurf"

# Install GUI
cp "$SCRIPT_DIR/ghostsurf-gui.sh" /usr/local/bin/ghostsurf-gui
chmod 755 /usr/local/bin/ghostsurf-gui
ok "ghostsurf-gui → /usr/local/bin/ghostsurf-gui"

# Auto-rotate script
cp "$SCRIPT_DIR/ghostsurf-auto.sh" /usr/local/bin/ghostsurf-auto.sh
chmod 755 /usr/local/bin/ghostsurf-auto.sh
ok "ghostsurf-auto.sh → /usr/local/bin/ghostsurf-auto.sh"

# Systemd service file (installed but not enabled by default)
if [[ -f "$SCRIPT_DIR/ghostsurf-autorotate.service" ]]; then
    cp "$SCRIPT_DIR/ghostsurf-autorotate.service" \
        /etc/systemd/system/ghostsurf-autorotate.service
    systemctl daemon-reload 2>/dev/null || true
    ok "ghostsurf-autorotate.service → /etc/systemd/system/"
fi

# Fix lib path in installed scripts (they need to find lib/ at runtime)
sed -i 's|$DIR/lib/|/usr/local/lib/ghostsurf/|g' \
    /usr/local/bin/ghostsurf /usr/local/bin/ghostsurf-gui 2>/dev/null || true

step "Step 4 — Desktop shortcut"
if [[ -f "$SCRIPT_DIR/ghostsurf.desktop" ]]; then
    cp "$SCRIPT_DIR/ghostsurf.desktop" /usr/share/applications/ghostsurf.desktop
    chmod 644 /usr/share/applications/ghostsurf.desktop
    update-desktop-database 2>/dev/null || true
    ok "Desktop shortcut installed"
fi

step "Step 5 — Tor service"
systemctl enable tor 2>/dev/null && ok "Tor enabled on startup" || warn "Could not enable Tor"

step "Step 6 — Verify"
command -v ghostsurf     &>/dev/null && ok "ghostsurf: ready"     || fail "ghostsurf not in PATH"
command -v ghostsurf-gui &>/dev/null && ok "ghostsurf-gui: ready" || warn "ghostsurf-gui missing"
command -v yad           &>/dev/null && ok "yad: installed"       || warn "yad missing"

trap - ERR SIGINT SIGTERM

echo ""
echo -e "  ${G}╔════════════════════════════════════════════╗${NC}"
echo -e "  ${G}║    GhostSurf v2.2 — Installed!  ✔         ║${NC}"
echo -e "  ${G}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${W}CLI:${NC}"
echo -e "    sudo ghostsurf start     ${D}← activate Tor routing${NC}"
echo -e "    sudo ghostsurf stop      ${D}← restore internet${NC}"
echo -e "    sudo ghostsurf verify    ${D}← 7-point leak test${NC}"
echo -e "    sudo ghostsurf rotate    ${D}← new exit IP${NC}"
echo ""
echo -e "  ${W}GUI:${NC}"
echo -e "    sudo ghostsurf-gui"
echo -e "    ${D}Or open 'GhostSurf v2.2' from applications menu${NC}"
echo ""
