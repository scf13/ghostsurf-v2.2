#!/usr/bin/env bash
# ── rules.sh — GhostSurf v2.2 iptables + DNS rules ───────────

# Source utils if not already loaded
UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${TOR_UID:-}" ]] && source "$UTILS_DIR/utils.sh"

RESOLV_BAK="/etc/resolv.conf.ghostsurf.bak"

# ═══════════════════════════════════════════════════════════════
#  APPLY RULES (called on start)
# ═══════════════════════════════════════════════════════════════
apply_rules() {
    # Save current state for restore
    iptables-save  > /tmp/ghostsurf.iptables.bak  2>/dev/null || true
    ip6tables-save > /tmp/ghostsurf.ip6tables.bak 2>/dev/null || true

    # ── Flush everything cleanly ──────────────────────────────
    iptables -F; iptables -X
    iptables -t nat -F; iptables -t nat -X
    iptables -t mangle -F

    # ── IPv6 hard block ───────────────────────────────────────
    ip6tables -F
    ip6tables -P INPUT   DROP
    ip6tables -P OUTPUT  DROP
    ip6tables -P FORWARD DROP

    # ── Default policies (OUTPUT ACCEPT — NAT handles routing) ─
    iptables -P INPUT   DROP
    iptables -P OUTPUT  ACCEPT
    iptables -P FORWARD DROP

    # ── Loopback ──────────────────────────────────────────────
    iptables -A INPUT  -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # ── Established connections ───────────────────────────────
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # ── DHCP ──────────────────────────────────────────────────
    iptables -A INPUT  -p udp --sport 67 --dport 68 -j ACCEPT
    iptables -A OUTPUT -p udp --sport 68 --dport 67 -j ACCEPT

    # ── LAN traffic (must be explicit in OUTPUT) ──────────────
    iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
    iptables -A OUTPUT -d 10.0.0.0/8     -j ACCEPT
    iptables -A OUTPUT -d 172.16.0.0/12  -j ACCEPT
    iptables -A OUTPUT -d 127.0.0.0/8    -j ACCEPT
    iptables -A INPUT  -s 192.168.0.0/16 -j ACCEPT
    iptables -A INPUT  -s 10.0.0.0/8     -j ACCEPT
    iptables -A INPUT  -s 172.16.0.0/12  -j ACCEPT

    # ── NAT rules — ORDER IS CRITICAL ────────────────────────

    # 1. Tor process must RETURN first — prevents routing loop
    iptables -t nat -A OUTPUT \
        -m owner --uid-owner "$TOR_UID" -j RETURN

    # 2. Skip NAT for all LAN/local subnets
    for subnet in $LAN; do
        iptables -t nat -A OUTPUT -d "$subnet" -j RETURN
    done

    # 3. DNS → Tor DNSPort
    iptables -t nat -A OUTPUT -p udp --dport 53 \
        -j REDIRECT --to-ports "$TOR_DNS_PORT"
    iptables -t nat -A OUTPUT -p tcp --dport 53 \
        -j REDIRECT --to-ports "$TOR_DNS_PORT"

    # 4. TCP → Tor TransPort (all other TCP)
    iptables -t nat -A OUTPUT -p tcp --syn \
        -j REDIRECT --to-ports "$TOR_TRANS_PORT"

    # ── Block external UDP (Tor is TCP only) ──────────────────
    iptables -A OUTPUT -p udp \
        ! -d 127.0.0.0/8 \
        ! -d 10.0.0.0/8  \
        ! -d 172.16.0.0/12 \
        ! -d 192.168.0.0/16 \
        -m owner ! --uid-owner "$TOR_UID" \
        -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || true

    gs_log "Rules applied — TOR_UID=$TOR_UID TransPort=$TOR_TRANS_PORT DNSPort=$TOR_DNS_PORT"
}

# ═══════════════════════════════════════════════════════════════
#  FLUSH RULES (called on stop)
# ═══════════════════════════════════════════════════════════════
flush_rules() {
    iptables -F; iptables -X
    iptables -t nat -F; iptables -t nat -X
    iptables -t mangle -F
    iptables -P INPUT   ACCEPT
    iptables -P OUTPUT  ACCEPT
    iptables -P FORWARD ACCEPT
    ip6tables -F
    ip6tables -P INPUT   ACCEPT
    ip6tables -P OUTPUT  ACCEPT
    ip6tables -P FORWARD ACCEPT

    # Restore saved rules if valid
    if [[ -s /tmp/ghostsurf.iptables.bak ]]; then
        iptables-restore --test < /tmp/ghostsurf.iptables.bak 2>/dev/null \
            && iptables-restore < /tmp/ghostsurf.iptables.bak 2>/dev/null \
            || true
    fi

    gs_log "Rules flushed — internet restored"
}

# ═══════════════════════════════════════════════════════════════
#  DNS LOCK / UNLOCK
# ═══════════════════════════════════════════════════════════════
dns_lock() {
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl stop dnsmasq         2>/dev/null || true
    [[ -f /etc/resolv.conf ]] && cp /etc/resolv.conf "$RESOLV_BAK"

    # Write Tor DNS — no chattr +i (breaks DHCP/Wi-Fi switching)
    cat > /etc/resolv.conf <<'EOF'
# GhostSurf v2.2 — DNS via Tor
nameserver 127.0.0.1
options ndots:0 attempts:1 timeout:5
EOF
    gs_log "DNS locked → 127.0.0.1 (Tor DNSPort $TOR_DNS_PORT)"
}

dns_unlock() {
    # Restore from backup
    if [[ -f "$RESOLV_BAK" ]]; then
        cp "$RESOLV_BAK" /etc/resolv.conf
    else
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    fi

    # Let system manager re-apply
    systemctl restart systemd-resolved 2>/dev/null || true
    nmcli general reload dns-rc        2>/dev/null || true

    gs_log "DNS restored"
}
