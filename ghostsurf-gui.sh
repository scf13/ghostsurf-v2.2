#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║     GhostSurf v2.2 — GUI (AnonSurf-style, Yad)              ║
# ║     Live status lights · Exit IP · Logs · One-click          ║
# ╚═══════════════════════════════════════════════════════════════╝

[[ $EUID -ne 0 ]] && exec sudo bash "$0" "$@"

# ── Dependency check ──────────────────────────────────────────
if ! command -v yad &>/dev/null; then
    apt-get install -y yad &>/dev/null \
        || { echo "yad not found. Install: sudo apt install yad"; exit 1; }
fi
if ! command -v ghostsurf &>/dev/null; then
    yad --error --title="GhostSurf v2.2" \
        --text="ghostsurf not found.\n\nRun installer:\n  sudo bash install.sh" \
        --button="OK:0" 2>/dev/null
    exit 1
fi

# ── Source utils for status checks ───────────────────────────
REAL="$(readlink -f "${BASH_SOURCE[0]}")"
DIR="$(cd "$(dirname "$REAL")" && pwd)"
[[ -f "$DIR/lib/utils.sh" ]] && source "$DIR/lib/utils.sh" \
    || source /usr/local/lib/ghostsurf/utils.sh 2>/dev/null || true

LOG_FILE="/var/log/ghostsurf.log"
STATE_FILE="/var/run/ghostsurf.state"
REFRESH=5   # auto-refresh seconds

# ─────────────────────────────────────────────────────────────
#  STATUS COLLECTORS
# ─────────────────────────────────────────────────────────────
_tor_ok()  { systemctl is-active --quiet tor 2>/dev/null; }
_nat_ok()  { iptables -t nat -L OUTPUT 2>/dev/null | grep -q "REDIRECT"; }
_dns_ok()  { grep -q "^nameserver 127.0.0.1" /etc/resolv.conf 2>/dev/null; }
_ipv6_ok() { ip6tables -L OUTPUT 2>/dev/null | grep -q "policy DROP"; }
_gs_active(){ [[ -f "$STATE_FILE" ]]; }

# ── Green / Red dot indicator ─────────────────────────────────
_dot() { $1 && echo "<span color='#00cc44'>⬤  ON</span>" \
             || echo "<span color='#cc2222'>⬤  OFF</span>"; }

# ── Status label for main banner ─────────────────────────────
_gs_label() {
    if _gs_active && _tor_ok; then
        echo "<span font='13' color='#00cc44'><b>● ACTIVE</b></span>"
    elif _tor_ok; then
        echo "<span font='13' color='#ccaa00'><b>● TOR ONLY</b></span>"
    else
        echo "<span font='13' color='#cc2222'><b>● INACTIVE</b></span>"
    fi
}

# ── Exit IP ───────────────────────────────────────────────────
_get_ip() {
    _tor_ok || { echo "not connected"; return; }
    torsocks curl -s --max-time 8 https://api64.ipify.org 2>/dev/null \
        || echo "unavailable"
}

# ── Uptime ────────────────────────────────────────────────────
_get_uptime() {
    [[ -f "$STATE_FILE" ]] || { echo "--"; return; }
    source "$STATE_FILE" 2>/dev/null || true
    local up=$(( $(date +%s) - ${STARTED:-$(date +%s)} ))
    printf "%02dh %02dm %02ds" $((up/3600)) $(((up%3600)/60)) $((up%60))
}

# ── Log tail (strip ANSI colors) ─────────────────────────────
_get_logs() {
    tail -n 20 "$LOG_FILE" 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | sed 's/\x1b(B//g' \
        || echo "(no log entries yet)"
}

# ─────────────────────────────────────────────────────────────
#  TERMINAL RUNNER
# ─────────────────────────────────────────────────────────────
_term() {
    local cmd="$1" title="${2:-GhostSurf v2.2}"
    if   command -v xterm        &>/dev/null; then
        xterm -title "$title" -fa "Monospace" -fs 11 \
              -bg "#0d0d14" -fg "#00e5cc" \
              -e bash -c "$cmd; echo ''; echo '[Done] Press Enter...'; read" &
    elif command -v gnome-terminal &>/dev/null; then
        gnome-terminal --title="$title" \
            -- bash -c "$cmd; echo; echo '[Done] Press Enter...'; read" &
    elif command -v xfce4-terminal &>/dev/null; then
        xfce4-terminal --title="$title" \
            --command="bash -c '$cmd; echo; read'" &
    else
        bash -c "$cmd" &
    fi
}

# ─────────────────────────────────────────────────────────────
#  MAIN WINDOW
# ─────────────────────────────────────────────────────────────
show_window() {
    # Collect all data before building window
    local gs_label tor_dot nat_dot dns_dot ipv6_dot exit_ip uptime logs

    gs_label=$(_gs_label)
    tor_dot=$(_dot _tor_ok)
    nat_dot=$(_dot _nat_ok)
    dns_dot=$(_dot _dns_ok)
    ipv6_dot=$(_dot _ipv6_ok)
    uptime=$(_get_uptime)
    exit_ip=$(_get_ip)
    logs=$(_get_logs)

    # Auto-rotate status
    local autorotate_status="⬤  OFF"
    if [[ -f "/var/run/ghostsurf-autorotate.pid" ]]; then
        local ar_pid; ar_pid=$(cat /var/run/ghostsurf-autorotate.pid)
        local ar_interval="?"
        [[ -f "/var/run/ghostsurf-autorotate.interval" ]] && \
            ar_interval=$(cat /var/run/ghostsurf-autorotate.interval)
        if kill -0 "$ar_pid" 2>/dev/null; then
            autorotate_status="<span color='#00cc44'>⬤  ON (every ${ar_interval}s)</span>"
        fi
    fi

    yad \
        --title="GhostSurf v2.2" \
        --window-icon="security-high" \
        --width=580 \
        --height=720 \
        --center \
        --no-escape \
        --form \
        --columns=2 \
        --separator="" \
        \
        --field="<b><span font='15' color='#00aaff'>GhostSurf v2.2</span></b>
<span size='small' color='gray'>Tor Transparent Proxy — AnonSurf-style</span>":LBL "" \
        --field="":LBL "" \
        \
        --field="$gs_label":LBL "" \
        --field="<span color='gray' size='small'>Uptime: $uptime</span>":LBL "" \
        \
        --field="":LBL "" \
        --field="":LBL "" \
        \
        --field="<b>── Status Indicators ────────</b>":LBL "" \
        --field="":LBL "" \
        \
        --field="Tor Service":LBL "" \
        --field="$tor_dot":LBL "" \
        \
        --field="Tor Routing (NAT)":LBL "" \
        --field="$nat_dot":LBL "" \
        \
        --field="DNS Protection":LBL "" \
        --field="$dns_dot":LBL "" \
        \
        --field="IPv6 Block":LBL "" \
        --field="$ipv6_dot":LBL "" \
        \
        --field="Auto-Rotate":LBL "" \
        --field="$autorotate_status":LBL "" \
        \
        --field="":LBL "" \
        --field="":LBL "" \
        \
        --field="<b>── Exit IP ──────────────────</b>":LBL "" \
        --field="":LBL "" \
        \
        --field="<span font='Monospace 14' color='#00cc66'><b>  $exit_ip</b></span>":LBL "" \
        --field="":LBL "" \
        \
        --field="":LBL "" \
        --field="":LBL "" \
        \
        --field="<b>── Controls ─────────────────</b>":LBL "" \
        --field="":LBL "" \
        \
        --field="<b>🟢  Start</b>":FBTN "bash -c 'xterm -title GhostSurf -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf start; echo; read\"'" \
        --field="<b>🔴  Stop</b>":FBTN  "bash -c 'xterm -title GhostSurf -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf stop; echo; read\"'" \
        \
        --field="<b>🔄  Restart</b>":FBTN "bash -c 'xterm -title GhostSurf -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf restart; echo; read\"'" \
        --field="<b>🔁  New IP</b>":FBTN  "bash -c 'xterm -title GhostSurf -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf rotate; echo; read\"'" \
        \
        --field="<b>🔍  Verify</b>":FBTN "bash -c 'xterm -title GhostSurf -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf verify; echo; read\"'" \
        --field="<b>📊  Status</b>":FBTN "bash -c 'xterm -title GhostSurf -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf status; echo; read\"'" \
        \
        --field="":LBL "" \
        --field="":LBL "" \
        \
        --field="<b>── Auto-Rotate ──────────────</b>":LBL "" \
        --field="":LBL "" \
        \
        --field="<b>⏱  Every 60s</b>":FBTN  "bash -c 'xterm -title \"GhostSurf AutoRotate\" -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf autorotate 60\"'" \
        --field="<b>⏱  Every 120s</b>":FBTN "bash -c 'xterm -title \"GhostSurf AutoRotate\" -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf autorotate 120\"'" \
        \
        --field="<b>⏱  Every 300s</b>":FBTN "bash -c 'xterm -title \"GhostSurf AutoRotate\" -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf autorotate 300\"'" \
        --field="<b>⏹  Stop Rotate</b>":FBTN "bash -c 'xterm -title \"GhostSurf AutoRotate\" -bg \"#0d0d14\" -fg \"#00e5cc\" -e bash -c \"ghostsurf autorotate stop; echo; read\"'" \
        \
        --field="":LBL "" \
        --field="":LBL "" \
        \
        --field="<b>── Log (last 20 lines) ──────</b>":LBL "" \
        --field="":LBL "" \
        \
        --field="$logs":TXT "" \
        \
        --button="🔄  Refresh:0" \
        --button="❌  Close:1" \
        2>/dev/null

    return $?
}

# ─────────────────────────────────────────────────────────────
#  SYSTEM TRAY (background icon)
# ─────────────────────────────────────────────────────────────
_tray() {
    (
        while true; do
            if _gs_active && _tor_ok; then
                echo "tooltip:GhostSurf v2.2 — Active"
                echo "icon:security-high"
            else
                echo "tooltip:GhostSurf v2.2 — Inactive"
                echo "icon:security-low"
            fi
            sleep "$REFRESH"
        done
    ) | yad --notification \
            --listen \
            --image="security-low" \
            --text="GhostSurf v2.2" \
        2>/dev/null &
}

# ─────────────────────────────────────────────────────────────
#  MAIN LOOP
# ─────────────────────────────────────────────────────────────
_tray 2>/dev/null || true

while true; do
    show_window
    code=$?
    case $code in
        0) continue ;;   # Refresh — redraw immediately
        *) break    ;;   # Close
    esac
done

pkill -f "yad --notification" 2>/dev/null || true
exit 0
