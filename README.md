# 👻 GhostSurf v2.2

> Tor Transparent Proxy for Kali Linux — AnonSurf-style

![Version](https://img.shields.io/badge/version-2.2-cyan)
![Platform](https://img.shields.io/badge/platform-Kali%20Linux-purple)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- ✅ System-wide Tor routing (all TCP → Tor automatically)
- ✅ DNS protection — no DNS leaks
- ✅ IPv6 fully blocked
- ✅ UDP blocked outside LAN
- ✅ Tor UID routing loop prevention
- ✅ LAN traffic kept local (DHCP/router access intact)
- ✅ Live Yad GUI with green/red status indicators
- ✅ 7-point leak verification test
- ✅ Auto network restore on stop or failure
- ✅ Modular structure (lib/rules.sh, lib/verify.sh, lib/utils.sh)

---

## Directory Structure

```
ghostsurf-v2.2/
├── ghostsurf.sh        ← CLI core (start, stop, restart, rotate, verify)
├── ghostsurf-gui.sh    ← Yad GUI (AnonSurf-style)
├── ghostsurf.desktop   ← Applications menu shortcut
├── install.sh          ← One-shot installer
└── lib/
    ├── utils.sh        ← Shared helpers, status checks, IP fetch
    ├── rules.sh        ← iptables + DNS rules
    └── verify.sh       ← 7-point leak test
```

---

## Install

```bash
git clone https://github.com/scf13/ghostsurf
cd ghostsurf
chmod +x ghostsurf.sh ghostsurf-gui.sh install.sh lib/*.sh
sudo bash install.sh
```

The installer will:
- Fix your network/DNS if broken before installing
- Install `tor`, `torsocks`, `yad`, `xterm`, and other dependencies
- Deploy CLI and GUI to `/usr/local/bin/`
- Add a desktop shortcut to your applications menu
- Enable Tor on system startup

---

## CLI Usage

```bash
sudo ghostsurf start    # Activate Tor routing
sudo ghostsurf stop     # Restore normal internet
sudo ghostsurf restart  # Stop then start cleanly
sudo ghostsurf status   # Show current state + exit IP
sudo ghostsurf ip       # Show current Tor exit IP
sudo ghostsurf rotate   # Request new Tor circuit (new exit IP)
sudo ghostsurf verify   # Run 7-point leak test
```

---

## GUI Usage

```bash
sudo ghostsurf-gui
```

Or find **GhostSurf v2.2** in your applications menu.

The GUI shows:
- 🟢/🔴 Live status lights for Tor, NAT routing, DNS, IPv6
- Current Tor exit IP in large green text
- Session uptime
- One-click buttons: Start, Stop, Restart, New IP, Verify, Status
- Live log panel (last 20 lines)
- System tray icon

---

## 🌐 Browser Setup (Important)

GhostSurf routes all TCP traffic through Tor automatically via
transparent proxy. For **extra security**, also configure your
browser to use Tor's SOCKS proxy directly:

### Proxy Settings

```
SOCKS Host : 127.0.0.1
Port       : 9050
Type       : SOCKS v5
```

### Firefox

1. Open **Settings** → Search **"Network Settings"** → Click **Settings...**
2. Select **Manual proxy configuration**
3. **SOCKS Host**: `127.0.0.1`
4. **Port**: `9050`
5. Select **SOCKS v5**
6. ✅ Check **Proxy DNS when using SOCKS v5**
7. Click **OK**

### Chromium / Chrome

```bash
chromium --proxy-server="socks5://127.0.0.1:9050"
```

### Any browser via proxychains

```bash
proxychains firefox
proxychains chromium
proxychains curl ifconfig.me
```

### Verify your browser is using Tor

Visit: **https://check.torproject.org**

You should see:
> *"Congratulations. This browser is configured to use Tor."*

Or check your IP:
```bash
curl --socks5-hostname 127.0.0.1:9050 ifconfig.me
```

---

## Network Recovery

If your internet stops working:

```bash
# Option 1 — GhostSurf stop (recommended)
sudo ghostsurf stop

# Option 2 — Manual restore
sudo iptables -F
sudo iptables -P OUTPUT ACCEPT
sudo iptables -t nat -F
sudo ip6tables -F
sudo ip6tables -P OUTPUT ACCEPT
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
sudo systemctl restart NetworkManager
```

---

## How It Works

```
Your Apps
    ↓
iptables NAT (OUTPUT chain)
    ↓
Tor TransPort 9040
    ↓
Tor Network (encrypted, multi-hop)
    ↓
Internet
```

**DNS flow:**
```
App DNS query (port 53)
    ↓
iptables NAT redirect
    ↓
Tor DNSPort 5353
    ↓
Resolved anonymously through Tor
```

---

## ⚠️ OPSEC Warnings

- ❌ Do **not** log into personal accounts (Google, email, social media) — breaks anonymity regardless of routing
- ❌ Do **not** open downloaded files while GhostSurf is active (PDFs, Office docs can phone home)
- ❌ Do **not** use your real name or personal details in anonymous sessions
- ✅ Use **Tor Browser** for maximum fingerprint protection
- ✅ Run `sudo ghostsurf verify` before sensitive work
- ✅ Run `sudo ghostsurf stop` when done

---

## Dependencies

| Package | Purpose |
|---|---|
| `tor` | Tor service |
| `torsocks` | Route specific apps through Tor |
| `iptables` | Transparent proxy rules |
| `yad` | GUI framework |
| `xterm` | Terminal for GUI buttons |
| `curl` | IP check |
| `dnsutils` | DNS test tools |
| `netcat-traditional` | Tor control port |

Install manually if needed:
```bash
sudo apt install -y tor torsocks yad xterm curl dnsutils netcat-traditional
```

---

## License

For authorized security research and privacy protection only.
MIT License — use responsibly.


---

## Auto-Rotate IP

Automatically change your Tor exit IP at a set interval.

### Option 1 — Temporary (stops on reboot)

```bash
sudo ghostsurf autorotate 120    # rotate every 2 minutes
sudo ghostsurf autorotate 60     # rotate every 1 minute
sudo ghostsurf autorotate 300    # rotate every 5 minutes
sudo ghostsurf autorotate stop   # stop rotating
sudo ghostsurf autorotate status # check if running
sudo ghostsurf autorotate log    # view rotation log
```

### Option 2 — Persistent (survives reboots)

```bash
# Install as systemd service — rotates every 10 minutes forever
sudo ghostsurf autorotate enable 600

# Check it is running
sudo systemctl status ghostsurf-autorotate

# Stop and remove the service
sudo ghostsurf autorotate disable
```

### Live output example

```
[14:22:01]  #1    185.220.101.47      → 95.142.46.213
[14:24:01]  #2    95.142.46.213       → 46.182.19.48
[14:26:01]  #3    46.182.19.48        → 178.17.170.23
```

### Rules

| Setting | Value |
|---|---|
| Minimum interval | 10 seconds |
| Recommended interval | 60 - 600 seconds |
| Log file | `/var/log/ghostsurf-autorotate.log` |
| Only rotates when | Tor is active |

> ⚠️ Very frequent rotation (under 30s) may cause connection failures.
> Recommended: 120-300 seconds for stable browsing.

---

## License

For authorized security research and privacy protection only.
MIT License — use responsibly.
