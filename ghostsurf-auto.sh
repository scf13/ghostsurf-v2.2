#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║     GhostSurf v2.2 — Auto-Rotate Script                      ║
# ║     Used by systemd service + direct CLI                      ║
# ╚═══════════════════════════════════════════════════════════════╝

INTERVAL="${1:-600}"   # default 10 minutes
LOG="/var/log/ghostsurf-autorotate.log"
TOR_CTRL_PORT=9051
COUNT=0

log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" | tee -a "$LOG"
}

rotate_now() {
    # Only rotate if GhostSurf is active
    if ! systemctl is-active --quiet tor; then
        log "SKIP — Tor not running"
        return 1
    fi

    local old_ip
    old_ip=$(torsocks curl -s --max-time 8 https://api64.ipify.org 2>/dev/null || echo "unknown")

    # Send NEWNYM signal
    echo -e 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT' | \
        nc -q 2 127.0.0.1 "$TOR_CTRL_PORT" &>/dev/null \
        || kill -HUP "$(pidof tor 2>/dev/null | awk '{print $1}')" 2>/dev/null \
        || { log "ERROR — Could not signal Tor"; return 1; }

    sleep 4  # wait for new circuit

    local new_ip
    new_ip=$(torsocks curl -s --max-time 8 https://api64.ipify.org 2>/dev/null || echo "unknown")
    ((COUNT++))

    log "Rotation #${COUNT} — ${old_ip} → ${new_ip} (interval: ${INTERVAL}s)"
    echo -e "  \033[0;36m[$(date '+%H:%M:%S')]\033[0m  #${COUNT}  \033[0;31m${old_ip}\033[0m → \033[0;32m${new_ip}\033[0m"
    return 0
}

# ── Main loop ─────────────────────────────────────────────────
log "Auto-rotate started — interval=${INTERVAL}s PID=$$"
echo -e "\n  \033[1;37mGhostSurf Auto-Rotate\033[0m — every ${INTERVAL}s"
echo -e "  \033[2mLog: $LOG\033[0m"
echo -e "  \033[2mStop: sudo ghostsurf autorotate stop\033[0m\n"

trap 'log "Auto-rotate stopped"; exit 0' SIGTERM SIGINT

while true; do
    sleep "$INTERVAL"
    rotate_now
done
