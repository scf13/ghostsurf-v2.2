#!/usr/bin/env bash
# ── verify.sh — GhostSurf v2.2 leak tests ────────────────────

UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${TOR_UID:-}" ]] && source "$UTILS_DIR/utils.sh"

# Colors
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2m'; NC='\033[0m'

_pass() { echo -e "  ${G}[✔]${NC} $*"; gs_log "VERIFY PASS: $*"; }
_fail() { echo -e "  ${R}[✘]${NC} $*"; gs_log "VERIFY FAIL: $*"; }
_warn() { echo -e "  ${Y}[!]${NC} $*"; gs_log "VERIFY WARN: $*"; }

# ═══════════════════════════════════════════════════════════════
#  RUN ALL 7 CHECKS
# ═══════════════════════════════════════════════════════════════
run_verify() {
    echo ""
    echo -e "  ${C}${W}GhostSurf v2.2 — Leak Test${NC}"
    echo -e "${D}  ─────────────────────────────────────────────────${NC}"
    echo ""

    local pass=0 fail=0 warn=0

    # ── Test 1: Tor service ───────────────────────────────────
    echo -e "  ${W}[1/7]${NC} Tor service"
    if tor_running; then
        _pass "Tor service: running"
        ((pass++))
    else
        _fail "Tor service: stopped"
        ((fail++))
    fi

    # ── Test 2: TransPort open ────────────────────────────────
    echo -e "  ${W}[2/7]${NC} Tor TransPort ${TOR_TRANS_PORT}"
    if trans_ready; then
        _pass "TransPort ${TOR_TRANS_PORT}: listening"
        ((pass++))
    else
        _fail "TransPort ${TOR_TRANS_PORT}: not open"
        ((fail++))
    fi

    # ── Test 3: NAT redirect active ───────────────────────────
    echo -e "  ${W}[3/7]${NC} iptables NAT redirect"
    if nat_active; then
        _pass "NAT: TCP redirect to Tor active"
        ((pass++))
    else
        _warn "NAT: no redirect rules found"
        ((warn++))
    fi

    # ── Test 4: DNS via Tor ───────────────────────────────────
    echo -e "  ${W}[4/7]${NC} DNS routing"
    if dns_locked; then
        _pass "DNS: nameserver 127.0.0.1 (Tor)"
        ((pass++))
    else
        local ns; ns=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
        _fail "DNS LEAK: nameserver is ${ns:-unknown} not 127.0.0.1"
        ((fail++))
    fi

    # ── Test 5: IPv6 blocked ──────────────────────────────────
    echo -e "  ${W}[5/7]${NC} IPv6 block"
    if ipv6_blocked; then
        _pass "IPv6: blocked (ip6tables OUTPUT DROP)"
        ((pass++))
    else
        _warn "IPv6: not blocked — potential leak"
        ((warn++))
    fi

    # ── Test 6: Live Tor routing ──────────────────────────────
    echo -e "  ${W}[6/7]${NC} Live Tor routing check"
    local chk; chk=$(torsocks curl -s --max-time 12 \
        https://check.torproject.org/api/ip 2>/dev/null || echo "{}")
    if echo "$chk" | grep -q '"IsTor":true'; then
        local ip; ip=$(echo "$chk" | grep -oP '"IP":"\K[^"]+' || echo "?")
        _pass "Tor routing confirmed — exit IP: $ip"
        ((pass++))
    elif echo "$chk" | grep -q '"IsTor":false'; then
        _fail "Traffic NOT going through Tor"
        ((fail++))
    else
        _warn "Tor check inconclusive (timeout or DNS issue)"
        ((warn++))
    fi

    # ── Test 7: Real IP blocked ───────────────────────────────
    echo -e "  ${W}[7/7]${NC} Real IP exposure"
    local direct; direct=$(curl -s --max-time 5 --noproxy '*' \
        https://api64.ipify.org 2>/dev/null || echo "BLOCKED")
    if [[ "$direct" == "BLOCKED" || -z "$direct" ]]; then
        _pass "Direct connection: blocked"
        ((pass++))
    else
        local tor_ip; tor_ip=$(get_exit_ip)
        if [[ "$direct" == "$tor_ip" && -n "$tor_ip" ]]; then
            _pass "Direct IP = Tor exit ($direct) — transparent proxy working"
            ((pass++))
        else
            _fail "REAL IP EXPOSED: $direct"
            ((fail++))
        fi
    fi

    # ── Score ─────────────────────────────────────────────────
    echo ""
    echo -e "${D}  ─────────────────────────────────────────────────${NC}"
    echo -e "  ${W}Results:${NC}  ${G}${pass} passed${NC}  ${Y}${warn} warned${NC}  ${R}${fail} failed${NC}"
    echo ""
    if   (( fail == 0 && warn == 0 )); then
        echo -e "  ${G}${W}PERFECT — All checks passed.${NC}"
    elif (( fail == 0 )); then
        echo -e "  ${Y}${W}GOOD — No critical failures. Review warnings.${NC}"
    else
        echo -e "  ${R}${W}ISSUES — Fix failures before sensitive work.${NC}"
        echo -e "  ${D}  Run: sudo ghostsurf restart${NC}"
    fi
    echo ""

    gs_log "Verify complete — PASS:$pass WARN:$warn FAIL:$fail"
}
