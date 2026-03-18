#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║          GhostSurf v2.2 — Anonymous Routing CLI              ║
# ╚═══════════════════════════════════════════════════════════════╝

set -uo pipefail

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

# ── Resolve script directory (works via symlink) ──────────────
REAL="$(readlink -f "${BASH_SOURCE[0]}")"
DIR="$(cd "$(dirname "$REAL")" && pwd)"

# ── Source modules ────────────────────────────────────────────
source "$DIR/lib/utils.sh"
source "$DIR/lib/rules.sh"
source "$DIR/lib/verify.sh"

# ── Colors ────────────────────────────────────────────────────
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2m'; NC='\033[0m'

_ok()   { echo -e "  ${G}[✔]${NC} $*"; }
_fail() { echo -e "  ${R}[✘]${NC} $*" >&2; }
_warn() { echo -e "  ${Y}[!]${NC} $*"; }
_step() { echo -e "  ${W}[*]${NC} $*"; }
_line() { echo -e "${D}  ─────────────────────────────────────────────────${NC}"; }

# ── Banner ────────────────────────────────────────────────────
_banner() {
echo -e "
${C}  ░██████╗░██╗  ██╗░█████╗░░██████╗████████╗░██████╗██╗   ██╗██████╗░███████╗
  ██╔════╝░██║  ██║██╔══██╗██╔════╝╚══██╔══╝██╔════╝██║   ██║██╔══██╗██╔════╝
  ██║░░██╗░███████║██║░░██║╚█████╗░   ██║   ╚█████╗░██║   ██║██████╔╝█████╗
  ██║░░╚██╗██╔══██║██║░░██║░╚═══██╗   ██║   ░╚═══██╗██║   ██║██╔══██╗██╔══╝
  ╚██████╔╝██║  ██║╚█████╔╝██████╔╝   ██║   ██████╔╝╚██████╔╝██║  ██║██║
  ░╚═════╝ ╚═╝  ╚═╝░╚════╝ ╚═════╝    ╚═╝   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝${NC}
${D}              v2.2 — Tor Transparent Proxy${NC}
"
}

# ── Torrc setup ───────────────────────────────────────────────
_configure_torrc() {
    local torrc="/etc/tor/torrc"
    [[ -f "$torrc" ]] && cp "$torrc" "${torrc}.bak"
    cat > "$torrc" <<EOF
# GhostSurf v2.2 — Tor Configuration
User debian-tor
VirtualAddrNetworkIPv4 10.192.0.0/10
AutomapHostsOnResolve 1
AutomapHostsSuffixes .onion,.exit
TransPort ${TOR_TRANS_PORT}
TransListenAddress 127.0.0.1
DNSPort ${TOR_DNS_PORT}
DNSListenAddress 127.0.0.1
SocksPort ${TOR_SOCKS_PORT}
ControlPort ${TOR_CTRL_PORT}
CookieAuthentication 0
MaxCircuitDirtiness 600
NewCircuitPeriod 30
CircuitBuildTimeout 15
NumEntryGuards 3
ExcludeExitNodes {cn},{ru},{by},{kp},{ir},{sy},{pk}
StrictNodes 1
Log notice file /var/log/tor/notices.log
EOF
}

# ── Safety trap — restore network if start fails ─────────────
_TRAP_ACTIVE=0
_restore_on_fail() {
    [[ $_TRAP_ACTIVE -eq 1 ]] && return 0
    _TRAP_ACTIVE=1
    trap '' ERR SIGINT SIGTERM
    [[ "${_CMD:-}" != "start" && "${_CMD:-}" != "restart" ]] && return 0
    echo ""
    _warn "Interrupted — restoring network..."
    flush_rules
    dns_unlock
    rm -f "$STATE_FILE" 2>/dev/null || true
    _ok "Network restored"
    gs_log "Emergency restore triggered"
}
trap '_restore_on_fail' ERR SIGINT SIGTERM

# ═══════════════════════════════════════════════════════════════
#  COMMANDS
# ═══════════════════════════════════════════════════════════════
cmd_start() {
    _banner
    [[ -f "$STATE_FILE" ]] && { _warn "Already running. Use: sudo ghostsurf stop"; exit 1; }

    _line
    echo -e "  ${W}${C}Activating GhostSurf v2.2...${NC}"
    _line; echo ""

    _step "Configuring Tor..."
    _configure_torrc

    _step "Starting Tor service..."
    systemctl stop tor 2>/dev/null || true
    sleep 1
    systemctl start tor

    # Wait for BOTH ports — iptables must not redirect until Tor is ready
    _step "Waiting for Tor to be fully ready..."
    local elapsed=0
    while ! (trans_ready && socks_ready); do
        sleep 1; ((elapsed++))
        printf "  ${C}⠿${NC}  TransPort: %s  SocksPort: %s  (%ds)\r" \
            "$(trans_ready && echo '✔' || echo '...')" \
            "$(socks_ready && echo '✔' || echo '...')" "$elapsed"
        [[ $elapsed -ge 90 ]] && {
            printf "%-60s\r" ""
            _fail "Tor not ready after 90s"
            _fail "Check: sudo journalctl -u tor --no-pager | tail -20"
            exit 1
        }
    done
    printf "%-60s\r" ""
    _ok "Tor ready — both ports open"

    _step "Locking DNS..."
    dns_lock

    _step "Applying iptables rules..."
    apply_rules

    echo "STARTED=$(date +%s)" > "$STATE_FILE"
    gs_log "GhostSurf v2.2 started — iface=$(ip route 2>/dev/null | awk '/default/{print $5;exit}')"

    echo ""
    _line
    _ok "${G}${W}GhostSurf is ACTIVE${NC}"
    _line; echo ""
    _ok "Tor TransPort  : ${TOR_TRANS_PORT}"
    _ok "Tor DNSPort    : ${TOR_DNS_PORT}"
    _ok "Tor SocksPort  : ${TOR_SOCKS_PORT}"

    sleep 2
    local ip; ip=$(get_exit_ip)
    _ok "Exit IP        : ${G}${W}${ip}${NC}"
    echo ""
    echo -e "  ${D}Verify: sudo ghostsurf verify${NC}"
    echo -e "  ${D}Stop:   sudo ghostsurf stop${NC}"
    echo ""
}

cmd_stop() {
    _banner
    _line
    echo -e "  ${W}${Y}Stopping GhostSurf v2.2...${NC}"
    _line; echo ""

    flush_rules && _ok "Firewall rules cleared"
    dns_unlock  && _ok "DNS restored"
    systemctl stop tor 2>/dev/null && _ok "Tor stopped" || _warn "Tor already stopped"
    rm -f "$STATE_FILE" 2>/dev/null || true

    gs_log "GhostSurf v2.2 stopped"
    echo ""
    _line
    _ok "${G}Network restored — normal internet active${NC}"
    _line; echo ""

    sleep 1
    ping -c 1 -W 3 1.1.1.1 &>/dev/null \
        && _ok "IP connectivity: OK" \
        || _warn "No ping — try: sudo systemctl restart NetworkManager"
    getent hosts google.com &>/dev/null \
        && _ok "DNS: OK" \
        || _warn "DNS not resolving — check /etc/resolv.conf"
    echo ""
}

cmd_restart() {
    _warn "Restarting GhostSurf..."
    cmd_stop; sleep 2; cmd_start
}

cmd_rotate() {
    _step "Requesting new Tor circuit..."
    tor_running || { _fail "Tor not running — start GhostSurf first"; exit 1; }

    # Send NEWNYM via control port
    echo -e 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT' | \
        nc -q 2 127.0.0.1 "$TOR_CTRL_PORT" &>/dev/null \
        && _ok "New Tor circuit requested" \
        || { _warn "Control port unreachable — using SIGHUP fallback"
             kill -HUP "$(pidof tor 2>/dev/null | awk '{print $1}')" 2>/dev/null \
                && _ok "Tor reloaded via SIGHUP" \
                || _fail "Could not signal Tor"; }

    sleep 3
    local ip; ip=$(get_exit_ip)
    _ok "New exit IP: ${G}${W}${ip}${NC}"
    gs_log "Identity rotated — new exit: $ip"
}

cmd_status() {
    _banner
    _line
    echo -e "  ${W}${C}GhostSurf v2.2 Status${NC}"
    _line; echo ""

    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE" 2>/dev/null || true
        local up=$(( $(date +%s) - ${STARTED:-0} ))
        _ok "GhostSurf  : ${G}ACTIVE${NC}  uptime: ${D}$(printf "%02dh %02dm %02ds" $((up/3600)) $(((up%3600)/60)) $((up%60)))${NC}"
    else
        _warn "GhostSurf  : ${Y}NOT RUNNING${NC}"
    fi

    tor_running && _ok "Tor        : ${G}running${NC}" || _fail "Tor        : ${R}stopped${NC}"
    nat_active  && _ok "NAT rules  : ${G}active${NC}"  || _warn "NAT rules  : ${Y}inactive${NC}"
    ipv6_blocked && _ok "IPv6       : ${G}blocked${NC}" || _warn "IPv6       : ${Y}not blocked${NC}"
    dns_locked  && _ok "DNS        : ${G}127.0.0.1 (Tor)${NC}" \
                || { local ns; ns=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
                     _warn "DNS        : ${Y}${ns:-unknown}${NC}"; }

    echo ""
    _step "Checking exit IP..."
    local ip; ip=$(get_exit_ip)
    _ok "Exit IP    : ${G}${W}${ip}${NC}"
    echo ""
}

cmd_ip() {
    local ip; ip=$(get_exit_ip)
    echo -e "\n  ${G}${W}${ip}${NC}\n"
}

cmd_verify() { run_verify; }

cmd_help() {
    _banner
    echo -e "  ${W}Usage:${NC}  sudo ghostsurf <command>\n"
    echo -e "  ${C}Commands:${NC}"
    echo -e "    ${W}start${NC}    Activate Tor routing + DNS + IPv6 block"
    echo -e "    ${W}stop${NC}              Restore normal internet"
    echo -e "    ${W}restart${NC}           Stop then start cleanly"
    echo -e "    ${W}status${NC}            Show current protection state"
    echo -e "    ${W}ip${NC}                Show current Tor exit IP"
    echo -e "    ${W}rotate${NC}            Request new Tor circuit once"
    echo -e "    ${W}verify${NC}            Run 7-point leak test"
    echo -e "    ${W}autorotate <secs>${NC}  Auto-rotate every N seconds"
    echo -e "    ${W}autorotate stop${NC}    Stop auto-rotation"
    echo -e "    ${W}autorotate status${NC}  Check if auto-rotation is running"
    echo ""
    echo -e "  ${D}Examples:${NC}"
    echo -e "    sudo ghostsurf autorotate 120   ${D}← rotate every 2 minutes${NC}"
    echo -e "    sudo ghostsurf autorotate 60    ${D}← rotate every 1 minute${NC}"
    echo -e "    sudo ghostsurf autorotate stop  ${D}← stop rotating${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
#  AUTOROTATE
# ═══════════════════════════════════════════════════════════════
cmd_autorotate() {
    local sub="${1:-120}"

    case "$sub" in
        stop)   _autorotate_stop   ;;
        status) _autorotate_status ;;
        *)
            # Validate interval is a number
            if ! [[ "$sub" =~ ^[0-9]+$ ]]; then
                _fail "Invalid interval: $sub — must be a number (seconds)"
                echo -e "  ${D}Example: sudo ghostsurf autorotate 120${NC}"
                exit 1
            fi
            [[ "$sub" -lt 10 ]] && {
                _warn "Minimum interval is 10 seconds — setting to 10"
                sub=10
            }
            _autorotate_start "$sub"
            ;;
    esac
}

readonly AUTOROTATE_PID="/var/run/ghostsurf-autorotate.pid"
readonly AUTOROTATE_LOG="/var/run/ghostsurf-autorotate.interval"
readonly AUTOROTATE_SVCLOG="/var/log/ghostsurf-autorotate.log"
readonly AUTOROTATE_SERVICE="ghostsurf-autorotate"

cmd_autorotate() {
    local sub="${1:-help}"

    case "$sub" in
        stop)         _autorotate_stop         ;;
        status)       _autorotate_status       ;;
        enable)       _autorotate_enable "${2:-600}"  ;;  # systemd persistent
        disable)      _autorotate_disable      ;;
        log)          _autorotate_log          ;;
        [0-9]*)
            # Validate number
            if ! [[ "$sub" =~ ^[0-9]+$ ]]; then
                _fail "Invalid interval: $sub"
                exit 1
            fi
            [[ "$sub" -lt 10 ]] && { _warn "Minimum 10s — using 10"; sub=10; }
            _autorotate_start "$sub"
            ;;
        *)
            echo ""
            _info "Usage: sudo ghostsurf autorotate <option>"
            echo ""
            echo -e "  ${W}sudo ghostsurf autorotate 120${NC}        ${D}run every 2 min (stops on reboot)${NC}"
            echo -e "  ${W}sudo ghostsurf autorotate 60${NC}         ${D}run every 1 min${NC}"
            echo -e "  ${W}sudo ghostsurf autorotate stop${NC}       ${D}stop the daemon${NC}"
            echo -e "  ${W}sudo ghostsurf autorotate status${NC}     ${D}show status${NC}"
            echo -e "  ${W}sudo ghostsurf autorotate enable 600${NC} ${D}persistent (survives reboot)${NC}"
            echo -e "  ${W}sudo ghostsurf autorotate disable${NC}    ${D}remove persistent service${NC}"
            echo -e "  ${W}sudo ghostsurf autorotate log${NC}        ${D}show rotation log${NC}"
            echo ""
            ;;
    esac
}

# ── Start daemon (bash loop — stops on reboot) ────────────────
_autorotate_start() {
    local interval="$1"

    # Stop existing first
    _autorotate_stop 2>/dev/null || true

    # Safety: only rotate if GhostSurf/Tor is active
    if ! systemctl is-active --quiet tor; then
        _fail "Tor is not running — start GhostSurf first:"
        _info "  sudo ghostsurf start"
        exit 1
    fi

    _banner
    _line
    echo -e "  ${W}${C}Auto-Rotate — every ${interval}s${NC}"
    _line; echo ""
    _ok "Interval : ${G}every ${interval} seconds${NC}"
    _ok "Log file : ${G}${AUTOROTATE_SVCLOG}${NC}"
    _info "Stop     : ${W}sudo ghostsurf autorotate stop${NC}"
    _info "Persist  : ${W}sudo ghostsurf autorotate enable ${interval}${NC}"
    echo ""

    echo "$interval" > "$AUTOROTATE_LOG"

    # Launch daemon
    (
        local count=0
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Daemon started — interval=${interval}s PID=$$" \
            >> "$AUTOROTATE_SVCLOG"

        trap 'echo "[$(date '+%Y-%m-%d %H:%M:%S')] Daemon stopped" >> "$AUTOROTATE_SVCLOG"; exit 0' \
            SIGTERM SIGINT

        while true; do
            sleep "$interval"

            # Safety check before every rotation
            if ! systemctl is-active --quiet tor; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] SKIP — Tor not running" \
                    >> "$AUTOROTATE_SVCLOG"
                continue
            fi

            local old_ip
            old_ip=$(torsocks curl -s --max-time 8 https://api64.ipify.org \
                     2>/dev/null || echo "unknown")

            # Rotate via control port, fallback to SIGHUP
            echo -e 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT' | \
                nc -q 2 127.0.0.1 "$TOR_CTRL_PORT" &>/dev/null \
                || kill -HUP "$(pidof tor 2>/dev/null | awk '{print $1}')" \
                2>/dev/null || true

            sleep 4  # allow circuit rebuild

            local new_ip
            new_ip=$(torsocks curl -s --max-time 8 https://api64.ipify.org \
                     2>/dev/null || echo "unknown")
            ((count++))

            local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
            local ts_short; ts_short=$(date '+%H:%M:%S')

            echo "[$ts] Rotation #${count} — ${old_ip} → ${new_ip}" \
                >> "$AUTOROTATE_SVCLOG"

            printf "  ${C}[%s]${NC}  #%-3d  ${R}%-20s${NC} → ${G}%s${NC}\n" \
                "$ts_short" "$count" "$old_ip" "$new_ip"
        done
    ) &

    local pid=$!
    echo "$pid" > "$AUTOROTATE_PID"
    disown "$pid"

    _ok "Daemon started (PID: $pid)"
    echo ""
    _line
    echo -e "  ${D}Showing live rotations — Ctrl+C to detach (daemon keeps running)${NC}"
    _line; echo ""

    trap 'echo -e "\n  ${D}Detached. Daemon still running in background.${NC}\n"; exit 0' SIGINT

    # Live countdown display
    local tick=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1; ((tick++))
        local remaining=$(( interval - (tick % interval) ))
        printf "  ${D}Next rotation in %3ds...${NC}    \r" "$remaining"
    done
}

# ── Stop daemon ───────────────────────────────────────────────
_autorotate_stop() {
    local stopped=false

    # Stop background daemon
    if [[ -f "$AUTOROTATE_PID" ]]; then
        local pid; pid=$(cat "$AUTOROTATE_PID")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            _ok "Auto-rotate daemon stopped (PID: $pid)"
            stopped=true
        fi
        rm -f "$AUTOROTATE_PID" "$AUTOROTATE_LOG"
    fi

    # Also stop systemd service if running
    if systemctl is-active --quiet "$AUTOROTATE_SERVICE" 2>/dev/null; then
        systemctl stop "$AUTOROTATE_SERVICE" 2>/dev/null
        _ok "Systemd service stopped"
        stopped=true
    fi

    $stopped || _warn "Auto-rotate was not running"
    gs_log "Autorotate stopped"
}

# ── Status ────────────────────────────────────────────────────
_autorotate_status() {
    echo ""
    _line
    echo -e "  ${W}${C}Auto-Rotate Status${NC}"
    _line; echo ""

    # Bash daemon
    if [[ -f "$AUTOROTATE_PID" ]]; then
        local pid; pid=$(cat "$AUTOROTATE_PID")
        local iv="?"; [[ -f "$AUTOROTATE_LOG" ]] && iv=$(cat "$AUTOROTATE_LOG")
        if kill -0 "$pid" 2>/dev/null; then
            _ok "Bash daemon  : ${G}RUNNING${NC}  (PID: $pid, every ${iv}s)"
        else
            _warn "Bash daemon  : ${Y}STALE PID${NC} ($pid)"
            rm -f "$AUTOROTATE_PID" "$AUTOROTATE_LOG"
        fi
    else
        _warn "Bash daemon  : ${Y}NOT RUNNING${NC}"
    fi

    # Systemd service
    if systemctl is-active --quiet "$AUTOROTATE_SERVICE" 2>/dev/null; then
        _ok "Systemd svc  : ${G}ACTIVE${NC} (persistent — survives reboot)"
    elif systemctl is-enabled --quiet "$AUTOROTATE_SERVICE" 2>/dev/null; then
        _warn "Systemd svc  : ${Y}ENABLED but not running${NC}"
    else
        _info "Systemd svc  : ${D}not installed${NC}"
        _info "  Enable:  ${W}sudo ghostsurf autorotate enable 600${NC}"
    fi

    # Last rotations from log
    echo ""
    if [[ -f "$AUTOROTATE_SVCLOG" ]]; then
        echo -e "  ${W}Last 5 rotations:${NC}"
        grep "Rotation" "$AUTOROTATE_SVCLOG" 2>/dev/null | tail -5 | \
            while IFS= read -r line; do echo -e "  ${D}$line${NC}"; done
        [[ ! $(grep -c "Rotation" "$AUTOROTATE_SVCLOG" 2>/dev/null) -gt 0 ]] && \
            echo -e "  ${D}(no rotations logged yet)${NC}"
    else
        echo -e "  ${D}(no log found)${NC}"
    fi
    echo ""

    _info "Commands:"
    _info "  Stop:    ${W}sudo ghostsurf autorotate stop${NC}"
    _info "  Log:     ${W}sudo ghostsurf autorotate log${NC}"
    echo ""
}

# ── Enable systemd persistent service ────────────────────────
_autorotate_enable() {
    local interval="${1:-600}"
    _step "Installing systemd auto-rotate service (every ${interval}s)..."

    # Write service file
    cat > /etc/systemd/system/ghostsurf-autorotate.service <<EOF
[Unit]
Description=GhostSurf Auto-Rotate Tor Circuit
After=network.target tor.service
Requires=tor.service

[Service]
Type=simple
ExecStart=/usr/local/bin/ghostsurf-auto.sh ${interval}
Restart=on-failure
RestartSec=30
User=root
StandardOutput=append:${AUTOROTATE_SVCLOG}
StandardError=append:${AUTOROTATE_SVCLOG}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ghostsurf-autorotate
    systemctl start  ghostsurf-autorotate

    _ok "Service installed and started"
    _ok "Rotates every ${interval}s — survives reboots"
    _info "Disable: ${W}sudo ghostsurf autorotate disable${NC}"
    _info "Status:  ${W}sudo systemctl status ghostsurf-autorotate${NC}"
    gs_log "Autorotate systemd service enabled — interval=${interval}s"
}

# ── Disable systemd service ───────────────────────────────────
_autorotate_disable() {
    _step "Removing systemd auto-rotate service..."
    systemctl stop    ghostsurf-autorotate 2>/dev/null || true
    systemctl disable ghostsurf-autorotate 2>/dev/null || true
    rm -f /etc/systemd/system/ghostsurf-autorotate.service
    systemctl daemon-reload
    _ok "Systemd service removed"
    gs_log "Autorotate systemd service disabled"
}

# ── Show log ──────────────────────────────────────────────────
_autorotate_log() {
    echo ""
    if [[ -f "$AUTOROTATE_SVCLOG" ]]; then
        echo -e "  ${W}Auto-Rotate Log — ${AUTOROTATE_SVCLOG}${NC}\n"
        tail -30 "$AUTOROTATE_SVCLOG" | while IFS= read -r line; do
            echo -e "  ${D}$line${NC}"
        done
    else
        _warn "No log file found at ${AUTOROTATE_SVCLOG}"
    fi
    echo ""
}

_CMD="${1:-help}"; shift || true
case "$_CMD" in
    start)       cmd_start          ;;
    stop)        cmd_stop           ;;
    restart)     cmd_restart        ;;
    rotate)      cmd_rotate         ;;
    autorotate)  cmd_autorotate "$@" ;;
    status)      cmd_status         ;;
    ip)          cmd_ip             ;;
    verify)      cmd_verify         ;;
    help|-h)     cmd_help           ;;
    *) _fail "Unknown: $_CMD"; cmd_help; exit 1 ;;
esac
