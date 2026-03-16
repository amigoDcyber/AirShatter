# AirShatter
### Wireless Security Auditing Toolkit
**Developer:** amigoDcyber

---

## Legal Notice
This tool is for **authorized security testing and educational purposes only**.  
Only use on networks you own or have explicit written permission to test.

---

## Project Structure

```
AirShatter/
├── airshatter.sh              ← Main launcher
│
├── modules/
│   ├── interface_manager.sh   ← Monitor/managed mode control (wraps airmonitor.sh)
│   ├── scanner.sh             ← Network discovery (iw / airodump-ng)
│   ├── capture_manager.sh     ← Packet capture sessions
│   ├── analyzer.sh            ← Capture file inspection
│   └── crack_module.sh        ← Handshake password auditing (wraps cracker.sh)
│
├── core/
│   ├── colors.sh              ← Colors and print helpers
│   ├── logging.sh             ← Session logging
│   ├── interface_detection.sh ← Wireless interface detection
│   └── dependency_check.sh    ← Tool availability checks
│
├── tools/
│   ├── airmonitor.sh          ← Original monitor mode manager
│   └── cracker.sh             ← Original handshake analyzer
│
├── captures/                  ← Capture files saved here
└── logs/                      ← Session logs saved here
```

---

## Requirements

| Tool            | Package           | Purpose                    |
|-----------------|-------------------|----------------------------|
| aircrack-ng     | aircrack-ng       | Network analysis            |
| airodump-ng     | aircrack-ng       | Packet capture / scanning   |
| hashcat         | hashcat           | Password strength auditing  |
| hcxpcapngtool   | hcxtools          | Capture conversion          |
| iw              | iw                | Interface management        |
| xterm           | xterm             | Capture/scan terminal       |
| wireshark       | wireshark         | Traffic analysis (optional) |
| tshark          | tshark            | Traffic analysis (optional) |

### Install on Kali / Debian / Ubuntu
```bash
sudo apt install aircrack-ng hashcat hcxtools iw xterm wireshark tshark
```

### Install on Arch / Manjaro
```bash
sudo pacman -S aircrack-ng hashcat hcxtools iw xterm wireshark-qt wireshark-cli
```

---

## Running

```bash
chmod +x airshatter.sh
sudo ./airshatter.sh
```

---

## Menu Overview

```
[1]  Detect / Select Wireless Interface
[2]  Enable Monitor Mode
[3]  Scan Nearby Networks        (SSID / BSSID / Channel / Encryption)
[4]  Start Packet Capture        (lab analysis)
[5]  Analyze Capture File        (hcxpcapngtool + aircrack-ng + tshark)
[6]  Audit Handshake Password Strength
[7]  View Logs
[8]  Restore Managed Mode
[9]  Exit
```

---

## Workflow Example

```
1 → Select wlan0
2 → Enable monitor mode → wlan0mon
3 → Scan nearby networks (lab AP)
4 → Capture on target channel
5 → Inspect .cap file — verify handshake quality
6 → Audit password strength with your wordlist
7 → View session logs
8 → Restore managed mode
```

---

## Notes on Handshake Quality

Before auditing password strength, always run **option 5** to check:
- Are there complete 4-way EAPOL handshake pairs?
- Are M4 frames zeroed (corrupted)?
- Were there excessive deauth frames during capture?

Corrupted handshakes produce false results. AirShatter does **not** use
`hashcat --force`, which would silently accept invalid data.
