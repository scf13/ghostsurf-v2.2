# 👻 GhostSurf v2.2

> Tor Transparent Proxy for Kali Linux — AnonSurf-style

![Version](https://img.shields.io/badge/version-2.2-cyan)
![Platform](https://img.shields.io/badge/platform-Kali%20Linux-purple)
![Shell](https://img.shields.io/badge/language-Shell-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Stars](https://img.shields.io/github/stars/scf13/ghostsurf-v2.2?style=social)

---

## 📌 What is GhostSurf?

GhostSurf is a **system-wide Tor transparent proxy** for Kali Linux.
It automatically routes **all your traffic through Tor** — no manual proxy settings needed for most apps.

Built as a cleaner, more stable alternative to AnonSurf — with a live GUI, auto IP rotation, and 7-point leak verification.

---

## ✨ Features

- ✅ System-wide Tor routing — all TCP automatically goes through Tor
- ✅ DNS leak protection — all DNS queries routed through Tor
- ✅ IPv6 fully blocked — no IPv6 leaks
- ✅ UDP blocked outside LAN — no UDP leaks
- ✅ LAN traffic kept local — DHCP and router access intact
- ✅ Tor UID loop prevention — Tor never routes itself
- ✅ Auto network restore on stop or failure
- ✅ 7-point leak verification test
- ✅ Auto IP rotation — change exit node every X seconds
- ✅ Persistent rotation via systemd — survives reboots
- ✅ Live Yad GUI with green/red status indicators
- ✅ Modular structure — easy to read and modify

---

## 📁 Directory Structure

```
ghostsurf-v2.2/
├── ghostsurf.sh                 ← CLI core
├── ghostsurf-gui.sh             ← Yad GUI (AnonSurf-style)
├── ghostsurf-auto.sh            ← Auto-rotate daemon script
├── ghostsurf-autorotate.service ← Systemd persistent service
├── ghostsurf.desktop            ← Applications menu shortcut
├── install.sh                   ← One-shot installer
└── lib/
    ├── utils.sh                 ← Shared helpers + status checks
    ├── rules.sh                 ← iptables + DNS rules
    └── verify.sh                ← 7-point leak test
```

---

## ⚙️ Install

### From GitHub (recommended)

```bash
git clone https://github.com/scf13/ghostsurf-v2.2.git
cd ghostsurf-v2.2
chmod +x ghostsurf.sh ghostsurf-gui.sh ghostsurf-auto.sh install.sh lib/*.sh
sudo bash install.sh
```

The installer will automatically:
- Fix your network and DNS if broken before installing
- Install tor, torsocks, yad, xterm and other dependencies
- Deploy CLI and GUI to /usr/local/bin/
- Add a desktop shortcut to your applications menu
- Enable Tor on system startup

### Remove / Uninstall

```bash
sudo rm -f /usr/local/bin/ghostsurf
sudo rm -f /usr/local/bin/ghostsurf-gui
sudo rm -f /usr/local/bin/ghostsurf-auto.sh
sudo rm -rf /usr/local/lib/ghostsurf
sudo rm -f /usr/share/applications/ghostsurf.desktop
sudo systemctl disable ghostsurf-autorotate 2>/dev/null
sudo rm -f /etc/systemd/system/ghostsurf-autorotate.service
```

---

## 💻 CLI Usage

```bash
sudo ghostsurf start     # Activate Tor routing
sudo ghostsurf stop      # Restore normal internet
sudo ghostsurf restart   # Stop then start cleanly
sudo ghostsurf status    # Show current state + exit IP
sudo ghostsurf ip        # Show current Tor exit IP
sudo ghostsurf rotate    # Get new Tor exit node once
sudo ghostsurf verify    # Run 7-point leak test
```

---

## 🖥️ GUI Usage

```bash
sudo ghostsurf-gui
```

Or find **GhostSurf v2.2** in your applications menu.

The GUI shows:
- 🟢/🔴 Live status lights — Tor, NAT routing, DNS, IPv6, Auto-Rotate
- Current Tor exit IP in large green text
- Session uptime
- Buttons — Start, Stop, Restart, New IP, Verify, Status
- Auto-rotate buttons — 60s, 120s, 300s, Stop
- Live log panel (last 20 lines)
- System tray icon

---

## 🔄 Auto-Rotate IP

Automatically change your Tor exit IP at a set interval.

### Temporary (stops on reboot)

```bash
sudo ghostsurf autorotate 120    # rotate every 2 minutes
sudo ghostsurf autorotate 60     # rotate every 1 minute
sudo ghostsurf autorotate 300    # rotate every 5 minutes
sudo ghostsurf autorotate stop   # stop rotating
sudo ghostsurf autorotate status # check if running
sudo ghostsurf autorotate log    # view rotation log
```

### Persistent (survives reboots)

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

> Minimum interval: 10 seconds. Recommended: 60-300 seconds.

---

## 🌐 Browser Setup (Important)

GhostSurf routes all TCP through Tor automatically.
For extra security, also set your browser proxy manually:

```
SOCKS Host : 127.0.0.1
Port       : 9050
Type       : SOCKS v5
```

### Firefox

1. Open Settings → Network Settings → Settings...
2. Select Manual proxy configuration
3. SOCKS Host: 127.0.0.1 — Port: 9050
4. Select SOCKS v5
5. Check Proxy DNS when using SOCKS v5
6. Click OK

### Chromium / Chrome

```bash
chromium --proxy-server="socks5://127.0.0.1:9050"
```

### Any app via proxychains

```bash
proxychains firefox
proxychains nmap -sT target.com
proxychains curl ifconfig.me
```

### Verify it is working

Visit: https://check.torproject.org

Or run:
```bash
curl --socks5-hostname 127.0.0.1:9050 ifconfig.me
```

---

## 🔧 Network Recovery

If your internet stops working:

```bash
# Option 1 — GhostSurf stop
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

## 🧱 How It Works

```
Your Apps
    ↓
iptables NAT (OUTPUT chain)
    ↓
Tor TransPort 9040
    ↓
Tor Network (encrypted multi-hop)
    ↓
Internet
```

DNS flow:
```
App DNS query → iptables redirect → Tor DNSPort 5353 → resolved anonymously
```

---

## ⚠️ OPSEC Warnings

- Do NOT log into personal accounts — breaks anonymity
- Do NOT open downloaded files while active — PDFs can phone home
- Do NOT use your real name or personal details
- Use Tor Browser for maximum fingerprint protection
- Run sudo ghostsurf verify before sensitive work
- Run sudo ghostsurf stop when done

---

## 📦 Dependencies

| Package | Purpose |
|---|---|
| tor | Tor service |
| torsocks | Route specific apps through Tor |
| iptables | Transparent proxy rules |
| yad | GUI framework |
| xterm | Terminal for GUI buttons |
| curl | IP check |
| dnsutils | DNS test tools |
| netcat-traditional | Tor control port communication |

Install manually if needed:
```bash
sudo apt install -y tor torsocks yad xterm curl dnsutils netcat-traditional
```

---

## 🤝 Contributing

Pull requests are welcome!

1. Fork the repo
2. Create a branch: `git checkout -b feature/your-feature`
3. Commit: `git commit -m "Add your feature"`
4. Push: `git push origin feature/your-feature`
5. Open a Pull Request

Report bugs by opening an Issue on GitHub.

---

## 📜 License

MIT License — for authorized security research and privacy protection only.

---

## ⭐ Support

If GhostSurf helped you — give it a star on GitHub!

https://github.com/scf13/ghostsurf-v2.2
