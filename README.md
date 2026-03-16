<div align="center">

```
    ╔═══════════════════════════════════════════════════════════╗
    ║      ▄▄▄       ███▄ ▄███▓ ██▓  ▄████  ▒█████            ║
    ║     ▒████▄    ▓██▒▀█▀ ██▒▓██▒ ██▒ ▀█▒▒██▒  ██▒          ║
    ║     ▒██  ▀█▄  ▓██    ▓██░▒██▒▒██░▄▄▄░▒██░  ██▒          ║
    ║     ░██▄▄▄▄██ ▒██    ▒██ ░██░░▓█  ██▓▒██   ██░          ║
    ║      ▓█   ▓██▒▒██▒   ░██▒░██░░▒▓███▀▒░ ████▓▒░          ║
    ║      ▒▒   ▓▒█░░ ▒░   ░  ░░▓   ░▒   ▒ ░ ▒░▒░▒░           ║
    ║       ▒   ▒▒ ░░  ░      ░ ▒ ░  ░   ░   ░ ▒ ▒░           ║
    ║       ░   ▒   ░      ░    ▒ ░░ ░   ░ ░ ░ ░ ▒            ║
    ║       ▄████▄▓██   ██▓ ▄▄▄▄   ▓█████  ██▀███            ║
    ║      ▒██▀ ▀█ ▒██  ██▒▓█████▄ ▓█   ▀ ▓██ ▒ ██▒          ║
    ║      ▒▓█    ▄ ▒██ ██░▒██▒ ▄██▒███   ▓██ ░▄█ ▒          ║
    ║      ▒▓▓▄ ▄██▒░ ▐██▓░▒██░█▀  ▒▓█  ▄ ▒██▀▀█▄            ║
    ║      ▒ ▓███▀ ░░ ██▒▓░░▓█  ▀█▓░▒████▒░██▓ ▒██▒          ║
    ╚═══════════════════════════════════════════════════════════╝
```

# AirShatter

**Professional Wireless Security Auditing Toolkit**

[![Bash](https://img.shields.io/badge/language-Bash-green?style=flat-square&logo=gnubash)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux-blue?style=flat-square&logo=linux)](https://kernel.org)
[![License](https://img.shields.io/badge/license-MIT-orange?style=flat-square)](LICENSE)
[![Requires](https://img.shields.io/badge/requires-Airmonitor-red?style=flat-square)](https://github.com/amigoDcyber/Airmonitor)
[![Version](https://img.shields.io/badge/version-1.1-cyan?style=flat-square)]()

*Developed by [amigoDcyber](https://github.com/amigoDcyber)*

</div>

---

## ⚠️ Legal Disclaimer

> **This tool is for authorized security testing and educational purposes only.**
> Only use AirShatter on networks and devices you **own** or have **explicit written permission** to test.
> Unauthorized use is illegal and may result in criminal prosecution.
> The developer assumes no liability for misuse.

---

## What is AirShatter?

AirShatter is a modular wireless security auditing toolkit written entirely in Bash. It combines the most common Wi-Fi security testing workflows into a single clean terminal interface — from interface management and multi-band scanning, all the way through automated handshake capture and password strength auditing.

It is designed to work across Kali Linux, Arch, Debian, and Ubuntu, and integrates with **[Airmonitor](https://github.com/amigoDcyber/Airmonitor)** for interface control and driver recovery.

---

## ⚡ Required — Install Airmonitor First

> AirShatter **depends on Airmonitor** for monitor mode management and interface driver recovery.
> Without it, options 2, 7, and 9 will not work.

```bash
git clone https://github.com/amigoDcyber/Airmonitor
cp Airmonitor/airmonitor.sh AirShatter/tools/airmonitor.sh
```

➡️ **[Airmonitor on GitHub](https://github.com/amigoDcyber/Airmonitor)**

---

## Features

| Module | Description |
|---|---|
| **Interface Manager** | Auto-detect wireless adapters, select interface, enable/disable monitor mode |
| **Multi-Band Scanner** | Scan 2.4GHz, 5GHz, and 6GHz bands using `iw` or `airodump-ng` |
| **Auto Handshake Capture** | Airgeddon-style — `airodump-ng` + `aireplay-ng` deauth loop, stops automatically when handshake is detected |
| **Passive Capture** | Capture-only mode, waits for natural client authentication |
| **Capture Analyzer** | Inspect `.cap`/`.pcap` with `hcxpcapngtool`, `aircrack-ng`, `tshark`, `wireshark` |
| **Password Auditor** | Audit WPA handshake password strength using `hashcat` mode 22000, no `--force` |
| **Interface Recovery** | Full driver recovery — managed mode restore + `modprobe` kernel driver reload via Airmonitor |
| **Session Logging** | Timestamped structured logs in `logs/` with per-module context |

---

## Installation

```bash
# 1. Clone AirShatter
git clone https://github.com/amigoDcyber/AirShatter
cd AirShatter

# 2. Install Airmonitor (required)
git clone https://github.com/amigoDcyber/Airmonitor
cp Airmonitor/airmonitor.sh tools/airmonitor.sh

# 3. Make executable
chmod +x airshatter.sh

# 4. Run
sudo ./airshatter.sh
```

---

## System Requirements

### Kali Linux / Debian / Ubuntu

```bash
sudo apt update
sudo apt install aircrack-ng hashcat hcxtools iw iproute2 \
                 xterm wireshark tshark tcpdump ethtool
```

### Arch Linux / Manjaro

```bash
sudo pacman -S aircrack-ng hashcat hcxtools iw iproute2 \
               xterm wireshark-qt wireshark-cli tcpdump ethtool
```

### Full Dependency Table

| Tool | Package | Required |
|---|---|---|
| aircrack-ng / airodump-ng / aireplay-ng / airmon-ng | `aircrack-ng` | ✅ Required |
| hashcat | `hashcat` | ✅ Required |
| hcxpcapngtool | `hcxtools` | ✅ Required |
| iw | `iw` | ✅ Required |
| ip | `iproute2` | ✅ Required |
| Airmonitor | [github.com/amigoDcyber/Airmonitor](https://github.com/amigoDcyber/Airmonitor) | ✅ Required |
| xterm | `xterm` | ⚡ Recommended |
| ethtool | `ethtool` | ⚡ Recommended |
| wireshark | `wireshark` | Optional |
| tshark | `tshark` | Optional |
| tcpdump | `tcpdump` | Optional |
| capinfos | `wireshark` | Optional |

---

## Project Structure

```
AirShatter/
├── airshatter.sh              ← Main launcher
│
├── modules/
│   ├── interface_manager.sh   ← Monitor/managed mode (wraps Airmonitor)
│   ├── scanner.sh             ← Multi-band network discovery
│   ├── capture_manager.sh     ← Auto + passive handshake capture
│   ├── analyzer.sh            ← Capture file inspection
│   ├── crack_module.sh        ← Password strength audit (hashcat)
│   └── interface_recovery.sh  ← Driver reload + managed mode restore
│
├── core/
│   ├── colors.sh              ← Terminal colors and print helpers
│   ├── logging.sh             ← Structured session logging
│   ├── interface_detection.sh ← Wireless adapter auto-detection
│   └── dependency_check.sh    ← Tool availability + install hints
│
├── tools/
│   ├── airmonitor.sh          ← Place Airmonitor here after cloning
│   └── cracker.sh             ← Standalone handshake analyzer
│
├── captures/                  ← Capture files saved here
├── logs/                      ← Session logs saved here
└── requirements.txt           ← Full dependency list
```

---

## Main Menu

```
  [1]  Select Wireless Interface
  [2]  Enable Monitor Mode
  [3]  Scan Networks                 (multi-band: 2.4 / 5 / 6 GHz)
  [4]  Capture Handshake             (auto deauth + capture, or passive)
  [5]  Analyze Capture File          (inspect .cap/.pcap)
  [6]  Password Strength Audit       (hashcat)
  [7]  Interface Recovery            (airmonitor recovery + driver reload)
  [8]  View Logs
  [9]  Restore Managed Mode
  [0]  Exit
```

---

## Typical Workflow

```
1  →  Select your wireless adapter (e.g. wlan0)
2  →  Enable monitor mode → wlan0mon
3  →  Scan nearby networks — identify your lab AP
4  →  Auto Capture: pick target → deauth loop → handshake auto-detected ✓
5  →  Analyze the .cap file — verify EAPOL handshake quality
6  →  Audit password strength with rockyou or custom wordlist
9  →  Restore managed mode when done
```

---

## Handshake Capture Modes

| Mode | How it works |
|---|---|
| **Auto** | `airodump-ng` runs in background + `aireplay-ng` deauth loop in foreground. Polls for valid EAPOL handshake every 5s. Stops both processes automatically when captured. |
| **Passive** | `airodump-ng` only — no deauth sent. Waits for a client to authenticate naturally. |
| **Broad** | All channels, no BSSID filter. Saves everything to a `.cap` file via xterm. |

---

## Notes on Handshake Quality

Before auditing password strength always run **option 5** first to verify:

- Are there complete 4-way EAPOL handshake pairs?
- Are M4 frames zeroed (corrupted capture)?
- Were there excessive deauth frames during capture?

AirShatter does **not** use `hashcat --force` — corrupted handshakes are rejected rather than producing false positives.

---

## Hardware

Your Wi-Fi adapter must support **monitor mode** and **packet injection** for full functionality.

Recommended adapters:
- Alfa AWUS036ACH — RTL8812AU
- Alfa AWUS036NHA — AR9271
- TP-Link TL-WN722N v1 — AR9271

Test injection support:
```bash
sudo aireplay-ng --test <interface>
```

---

## Related Projects

- **[Airmonitor](https://github.com/amigoDcyber/Airmonitor)** — Wireless interface manager *(required)*

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">
<sub>Built by amigoDcyber • For authorized security testing and education only</sub>
</div>
