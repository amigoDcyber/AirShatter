#!/bin/bash
# =============================================================================
# AirShatter — airshatter.sh
# Professional Wireless Security Auditing Toolkit
# Developer: amigoDcyber
# Version: 1.1
#
# Usage: sudo ./airshatter.sh
# =============================================================================

# ─── Resolve project root (works regardless of where you call it from) ────────
AS_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
export AS_ROOT

LOG_DIR="$AS_ROOT/logs"
export LOG_DIR

# ─── Source core modules ──────────────────────────────────────────────────────
_source_core() {
    local f
    for f in colors logging interface_detection dependency_check; do
        local path="$AS_ROOT/core/${f}.sh"
        if [[ ! -f "$path" ]]; then
            echo "FATAL: Missing core module: $path"
            exit 1
        fi
        # shellcheck source=/dev/null
        source "$path"
    done
}

# ─── Source feature modules ───────────────────────────────────────────────────
_source_modules() {
    local f
    for f in interface_manager scanner capture_manager analyzer crack_module interface_recovery client_test; do
        local path="$AS_ROOT/modules/${f}.sh"
        if [[ ! -f "$path" ]]; then
            echo "WARNING: Missing module: $path"
            continue
        fi
        # shellcheck source=/dev/null
        source "$path"
    done
}

# ─── Banner ───────────────────────────────────────────────────────────────────
show_banner() {
    clear
    echo -e "${BRED}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║      ▄▄▄       ███▄ ▄███▓ ██▓  ▄████  ▒█████            ║
    ║     ▒████▄    ▓██▒▀█▀ ██▒▓██▒ ██▒ ▀█▒▒██▒  ██▒          ║
    ║     ▒██  ▀█▄  ▓██    ▓██░▒██▒▒██░▄▄▄░▒██░  ██▒          ║
    ║     ░██▄▄▄▄██ ▒██    ▒██ ░██░░▓█  ██▓▒██   ██░          ║
    ║      ▓█   ▓██▒▒██▒   ░██▒░██░░▒▓███▀▒░ ████▓▒░          ║
    ║      ▒▒   ▓▒█░░ ▒░   ░  ░░▓   ░▒   ▒ ░ ▒░▒░▒░           ║
    ║       ▒   ▒▒ ░░  ░      ░ ▒ ░  ░   ░   ░ ▒ ▒░           ║
    ║       ░   ▒   ░      ░    ▒ ░░ ░   ░ ░ ░ ░ ▒            ║
    ║           ░  ░       ░    ░        ░     ░ ░            ║
    ║                                                          ║
    ║       ▄████▄▓██   ██▓ ▄▄▄▄   ▓█████  ██▀███            ║
    ║      ▒██▀ ▀█ ▒██  ██▒▓█████▄ ▓█   ▀ ▓██ ▒ ██▒          ║
    ║      ▒▓█    ▄ ▒██ ██░▒██▒ ▄██▒███   ▓██ ░▄█ ▒          ║
    ║      ▒▓▓▄ ▄██▒░ ▐██▓░▒██░█▀  ▒▓█  ▄ ▒██▀▀█▄            ║
    ║      ▒ ▓███▀ ░░ ██▒▓░░▓█  ▀█▓░▒████▒░██▓ ▒██▒          ║
    ║      ░ ░▒ ▒  ░ ██▒▒▒ ░▒▓███▀▒░░ ▒░ ░░ ▒▓ ░▒▓░          ║
    ║        ░  ▒ ▓██ ░▒░ ▒░▒   ░  ░ ░  ░  ░▒ ░ ▒░          ║
    ║      ░     ▒ ▒ ░░  ░  ░    ░    ░     ░░   ░           ║
    ║      ░ ░   ░ ░     ░  ░         ░  ░   ░               ║
    ║      ░     ░ ░            ░                            ║
    ║                                                          ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${BCYAN}         ⚡  AirShatter — Wireless Security Auditing Toolkit  ⚡${NC}"
    echo -e "${GRAY}                   Developer: ${BGREEN}amigoDcyber${NC}  ${GRAY}v1.1${NC}"
    echo -e "${BRED}            ════════════════════════════════════════════════${NC}"
    echo

    # Status bar — shows active interface info when one is selected
    if [[ -n "$SELECTED_IFACE" ]]; then
        local mode
        mode=$(iw dev "$SELECTED_IFACE" info 2>/dev/null | awk '/type/{print $2}')
        echo -e "  ${GRAY}Interface: ${BGREEN}${SELECTED_IFACE}${NC}  ${GRAY}Mode: ${BCYAN}${mode:-managed}${NC}  ${GRAY}Monitor: ${BYELLOW}${MONITOR_IFACE:-(none)}${NC}"
        echo
    fi
}

# ─── Disclaimer (shown once at startup) ───────────────────────────────────────
show_disclaimer() {
    echo
    echo -e "${BYELLOW}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BYELLOW}  ║               ⚠  LEGAL DISCLAIMER                       ║${NC}"
    echo -e "${BYELLOW}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BYELLOW}  ║${NC}  This tool is for ${WHITE}authorized security testing${NC} and         ${BYELLOW}║${NC}"
    echo -e "${BYELLOW}  ║${NC}  ${WHITE}educational purposes only${NC}.                              ${BYELLOW}║${NC}"
    echo -e "${BYELLOW}  ║${NC}                                                          ${BYELLOW}║${NC}"
    echo -e "${BYELLOW}  ║${NC}  Only use on networks and devices you ${WHITE}own or have${NC}        ${BYELLOW}║${NC}"
    echo -e "${BYELLOW}  ║${NC}  ${WHITE}explicit written permission${NC} to test.                   ${BYELLOW}║${NC}"
    echo -e "${BYELLOW}  ║${NC}                                                          ${BYELLOW}║${NC}"
    echo -e "${BYELLOW}  ║${NC}  Unauthorized use may be illegal in your jurisdiction.  ${BYELLOW}║${NC}"
    echo -e "${BYELLOW}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    read -rp "$(echo -e "  ${BPURPLE}I understand and agree [y/N]${NC}: ")" ack
    [[ "${ack,,}" != "y" ]] && {
        echo -e "\n${GRAY}  Exiting.${NC}\n"
        exit 0
    }
    log_info "Disclaimer acknowledged"
}

# ─── Main menu ────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        show_banner

        echo -e "  ${BCYAN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${BCYAN}║${NC}  ${WHITE}AirShatter — Main Menu                          ${NC}${BCYAN}║${NC}"
        echo -e "  ${BCYAN}╚════════════════════════════════════════════════════╝${NC}"
        echo

        echo -e "  ${GRAY}── Interface ────────────────────────────────────────${NC}"
        echo -e "  ${BGREEN}[1]${NC}  ${WHITE}Select Wireless Interface${NC}"
        echo -e "  ${BGREEN}[2]${NC}  ${WHITE}Enable Monitor Mode${NC}"
        echo
        echo -e "  ${GRAY}── Discovery & Capture ──────────────────────────────${NC}"
        echo -e "  ${BGREEN}[3]${NC}  ${WHITE}Scan Networks${NC}                 ${GRAY}(multi-band)${NC}"
        echo -e "  ${BGREEN}[4]${NC}  ${WHITE}Capture Handshake${NC}             ${GRAY}(auto deauth + capture, or passive)${NC}"
        echo
        echo -e "  ${GRAY}── Analysis & Auditing ──────────────────────────────${NC}"
        echo -e "  ${BGREEN}[5]${NC}  ${WHITE}Analyze Capture File${NC}          ${GRAY}(inspect .cap/.pcap)${NC}"
        echo -e "  ${BGREEN}[6]${NC}  ${WHITE}Password Strength Audit${NC}       ${GRAY}(hashcat)${NC}"
        echo
        echo -e "  ${GRAY}── Recovery & Control ───────────────────────────────${NC}"
        echo -e "  ${BCYAN}[7]${NC}  ${WHITE}Interface Recovery${NC}            ${GRAY}(airmonitor recovery mode)${NC}"
        echo -e "  ${BGREEN}[8]${NC}  ${WHITE}View Logs${NC}"
        echo -e "  ${BGREEN}[9]${NC}  ${WHITE}Restore Managed Mode${NC}"
        echo -e "  ${BPURPLE}[10]${NC}${WHITE} Lab Client Disconnect Test${NC}"
        echo
        echo -e "  ${BRED}[0]${NC}  ${WHITE}Exit${NC}"
        echo

        read -rp "$(echo -e "  ${BPURPLE}Choice [0-10]${NC}: ")" opt

        case "$opt" in
            1)
                select_interface
                log_action "MENU" "1 — interface select"
                ;;
            2)
                module_enable_monitor
                log_action "MENU" "2 — enable monitor"
                ;;
            3)
                module_scan_networks
                log_action "MENU" "3 — scan networks"
                ;;
            4)
                module_start_capture
                log_action "MENU" "4 — capture handshake"
                ;;
            5)
                module_analyze_capture
                log_action "MENU" "5 — analyze capture"
                ;;
            6)
                module_audit_password
                log_action "MENU" "6 — password audit"
                ;;
            7)
                module_interface_recovery
                log_action "MENU" "7 — interface recovery"
                ;;
            8)
                view_logs
                log_action "MENU" "8 — view logs"
                ;;
            9)
                module_restore_managed
                log_action "MENU" "9 — restore managed"
                ;;
            10)
                module_client_test
                log_action "MENU" "10 — client test"
                ;;
            0|q|Q)
                echo
                echo -e "${BGREEN}  ✓ Session complete. Stay legal. 👾${NC}"
                echo
                log_action "EXIT" "Session ended"
                log_separator
                exit 0
                ;;
            *)
                print_error "Invalid option: '$opt' — choose 0-10"
                sleep 0.5
                continue
                ;;
        esac

        pause
    done
}

# ─── Entry point ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "\n  ${BRED}[!]${NC} ${YELLOW}AirShatter requires root privileges.${NC}"
    echo -e "  ${GRAY}Run with: sudo ./airshatter.sh${NC}\n"
    exit 1
fi

_source_core
_source_modules

init_logging
mkdir -p "$AS_ROOT/captures" "$AS_ROOT/logs"

show_banner
show_disclaimer
sleep 0.5
check_all_dependencies
log_action "START" "AirShatter v1.1 — user=$(logname 2>/dev/null || echo root) host=$(hostname)"

main_menu
