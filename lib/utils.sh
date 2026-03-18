#!/usr/bin/env bash
# ── utils.sh — GhostSurf v2.2 shared helpers ─────────────────

LOG_FILE="/var/log/ghostsurf.log"
STATE_FILE="/var/run/ghostsurf.state"

TOR_SOCKS_PORT=9050
TOR_TRANS_PORT=9040
TOR_DNS_PORT=5353
TOR_CTRL_PORT=9051
TOR_UID=$(id -u debian-tor 2>/dev/null || id -u tor 2>/dev/null || echo 109)
LAN="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"

# ── Logging ───────────────────────────────────────────────────
gs_log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# ── Tor checks ────────────────────────────────────────────────
tor_running()   { systemctl is-active --quiet tor 2>/dev/null; }
trans_ready()   { ss -tlnp 2>/dev/null | grep -q ":${TOR_TRANS_PORT}"; }
socks_ready()   { ss -tlnp 2>/dev/null | grep -q ":${TOR_SOCKS_PORT}"; }

# ── Wait until both ports open ────────────────────────────────
wait_for_tor() {
    local elapsed=0
    while ! (trans_ready && socks_ready); do
        sleep 1; ((elapsed++))
        [[ $elapsed -ge 90 ]] && return 1
    done
    return 0
}

# ── IP helpers ────────────────────────────────────────────────
get_exit_ip() {
    torsocks curl -s --max-time 8 https://api64.ipify.org 2>/dev/null \
        || curl -s --socks5-hostname 127.0.0.1:${TOR_SOCKS_PORT} \
               --max-time 8 https://api64.ipify.org 2>/dev/null \
        || echo "unavailable"
}

# ── NAT check ─────────────────────────────────────────────────
nat_active()  { iptables -t nat -L OUTPUT 2>/dev/null | grep -q "REDIRECT"; }
ipv6_blocked(){ ip6tables -L OUTPUT 2>/dev/null | grep -q "policy DROP"; }
dns_locked()  {
    grep -q "^nameserver 127.0.0.1" /etc/resolv.conf 2>/dev/null
}
