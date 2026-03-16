#!/bin/bash
# =============================================================================
# AirShatter — tools/airmonitor.sh
# Wireless interface monitor/managed mode management
# Original script by amigoDcyber — integrated into AirShatter
# =============================================================================
#
# Usage (standalone):
#   sudo ./airmonitor.sh [enable|disable|refresh|status] [interface]
#
# Usage (called by modules/interface_manager.sh):
#   source tools/airmonitor.sh
#   airmonitor_enable  wlan0
#   airmonitor_disable wlan0mon
#   airmonitor_refresh wlan0
#   airmonitor_status  wlan0

# Guard against double-sourcing
[[ -n "$_AIRMONITOR_LOADED" ]] && return 0
_AIRMONITOR_LOADED=1

# Source colors if not already loaded
if [[ -z "$BGREEN" ]]; then
    _AM_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    # shellcheck source=../core/colors.sh
    source "$_AM_DIR/../core/colors.sh" 2>/dev/null || {
        # Minimal inline colors if core not available
        BRED='\033[1;31m'; BGREEN='\033[1;32m'; BCYAN='\033[1;36m'
        BYELLOW='\033[1;33m'; WHITE='\033[1;37m'; GRAY='\033[0;90m'; NC='\033[0m'
        print_success() { echo -e "${BGREEN}[✓]${NC} $*"; }
        print_error()   { echo -e "${BRED}[-]${NC} $*"; }
        print_info()    { echo -e "${BCYAN}[*]${NC} $*"; }
        print_warning() { echo -e "${BYELLOW}[!]${NC} $*"; }
    }
fi

# ─── Kill interfering processes ───────────────────────────────────────────────
_kill_interfering() {
    print_info "Killing interfering processes..."
    local procs=("NetworkManager" "wpa_supplicant" "dhclient" "dhcpcd")
    for p in "${procs[@]}"; do
        if pgrep -x "$p" &>/dev/null; then
            print_info "  Stopping $p..."
            pkill -x "$p" 2>/dev/null
            sleep 0.5
        fi
    done
}

# ─── Restore interfering processes ────────────────────────────────────────────
_restore_services() {
    print_info "Restoring network services..."
    if command -v systemctl &>/dev/null; then
        systemctl start NetworkManager 2>/dev/null && \
            print_info "  NetworkManager restarted"
        systemctl start wpa_supplicant 2>/dev/null
    fi
}

# ─── Enable monitor mode ──────────────────────────────────────────────────────
airmonitor_enable() {
    local iface="${1:-$SELECTED_IFACE}"

    if [[ -z "$iface" ]]; then
        print_error "No interface specified for monitor mode."
        return 1
    fi

    if ! ip link show "$iface" &>/dev/null; then
        print_error "Interface '$iface' does not exist."
        return 1
    fi

    # Check current mode
    local current_mode
    current_mode=$(iw dev "$iface" info 2>/dev/null | awk '/type/{print $2}')
    if [[ "$current_mode" == "monitor" ]]; then
        print_warning "$iface is already in monitor mode."
        MONITOR_IFACE="$iface"
        return 0
    fi

    print_info "Enabling monitor mode on $iface..."

    # Method 1: airmon-ng (preferred)
    if command -v airmon-ng &>/dev/null; then
        _kill_interfering
        airmon-ng start "$iface" 2>/dev/null

        # airmon-ng may rename interface to wlan0mon or phyX
        local mon_iface
        mon_iface=$(iw dev 2>/dev/null | awk '/Interface/{iface=$2} /type monitor/{print iface; exit}')

        if [[ -n "$mon_iface" ]]; then
            MONITOR_IFACE="$mon_iface"
            print_success "Monitor mode enabled → $MONITOR_IFACE"
            log_action "MONITOR_ENABLE" "Interface $iface → monitor mode as $MONITOR_IFACE (via airmon-ng)"
            return 0
        fi
    fi

    # Method 2: iw (manual)
    ip link set "$iface" down 2>/dev/null
    iw dev "$iface" set type monitor 2>/dev/null
    ip link set "$iface" up 2>/dev/null

    local new_mode
    new_mode=$(iw dev "$iface" info 2>/dev/null | awk '/type/{print $2}')
    if [[ "$new_mode" == "monitor" ]]; then
        MONITOR_IFACE="$iface"
        print_success "Monitor mode enabled → $MONITOR_IFACE (via iw)"
        log_action "MONITOR_ENABLE" "Interface $iface → monitor mode (via iw)"
        return 0
    fi

    print_error "Failed to enable monitor mode on $iface."
    log_error "Failed to enable monitor mode on $iface"
    return 1
}

# ─── Disable monitor mode / restore managed ───────────────────────────────────
airmonitor_disable() {
    local iface="${1:-$MONITOR_IFACE}"

    if [[ -z "$iface" ]]; then
        print_error "No monitor interface specified."
        return 1
    fi

    print_info "Restoring managed mode on $iface..."

    # Method 1: airmon-ng stop
    if command -v airmon-ng &>/dev/null; then
        airmon-ng stop "$iface" 2>/dev/null
        _restore_services
        # After stopping, original interface should be back
        local orig="${iface%mon}"
        if ip link show "$orig" &>/dev/null; then
            SELECTED_IFACE="$orig"
            MONITOR_IFACE=""
            print_success "Managed mode restored → $orig"
            log_action "MONITOR_DISABLE" "Monitor stopped, restored $orig"
            return 0
        fi
    fi

    # Method 2: iw
    ip link set "$iface" down 2>/dev/null
    iw dev "$iface" set type managed 2>/dev/null
    ip link set "$iface" up 2>/dev/null
    _restore_services

    local new_mode
    new_mode=$(iw dev "$iface" info 2>/dev/null | awk '/type/{print $2}')
    if [[ "$new_mode" == "managed" ]]; then
        MONITOR_IFACE=""
        print_success "Managed mode restored → $iface"
        log_action "MONITOR_DISABLE" "Interface $iface restored to managed (via iw)"
        return 0
    fi

    print_error "Failed to restore managed mode."
    log_error "Failed to restore managed mode on $iface"
    return 1
}

# ─── Refresh / recover interface ──────────────────────────────────────────────
airmonitor_refresh() {
    local iface="${1:-$SELECTED_IFACE}"

    if [[ -z "$iface" ]]; then
        print_error "No interface specified for refresh."
        return 1
    fi

    print_info "Refreshing interface $iface..."
    ip link set "$iface" down 2>/dev/null
    sleep 1
    ip link set "$iface" up 2>/dev/null
    sleep 1

    local state
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null)
    print_success "Interface $iface refreshed. State: ${state:-unknown}"
    log_action "REFRESH" "Interface $iface refreshed"
}

# ─── Status report ────────────────────────────────────────────────────────────
airmonitor_status() {
    local iface="${1:-$SELECTED_IFACE}"
    [[ -z "$iface" ]] && { print_warning "No interface selected."; return 1; }

    echo
    echo -e "  ${WHITE}Interface Status: ${BGREEN}$iface${NC}"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..40})${NC}"

    local mode mac state driver channel
    mode=$(iw dev "$iface" info 2>/dev/null | awk '/type/{print $2}')
    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null)
    driver=$(basename "$(readlink -f "/sys/class/net/$iface/device/driver" 2>/dev/null)" 2>/dev/null)
    channel=$(iw dev "$iface" info 2>/dev/null | awk '/channel/{print $2}')

    printf "  ${CYAN}%-12s${NC} %s\n" "Mode:"    "${mode:-unknown}"
    printf "  ${CYAN}%-12s${NC} %s\n" "MAC:"     "${mac:-unknown}"
    printf "  ${CYAN}%-12s${NC} %s\n" "State:"   "${state:-unknown}"
    printf "  ${CYAN}%-12s${NC} %s\n" "Driver:"  "${driver:-unknown}"
    printf "  ${CYAN}%-12s${NC} %s\n" "Channel:" "${channel:--}"
    echo
}

# ─── Standalone CLI entry point ───────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Running directly, not sourced
    source "$(dirname "$0")/../core/colors.sh" 2>/dev/null

    if [[ $EUID -ne 0 ]]; then
        echo "This script requires root privileges."
        exit 1
    fi

    cmd="${1:-status}"
    iface="$2"

    case "$cmd" in
        enable)  airmonitor_enable  "$iface" ;;
        disable) airmonitor_disable "$iface" ;;
        refresh) airmonitor_refresh "$iface" ;;
        status)  airmonitor_status  "$iface" ;;
        *)
            echo "Usage: $0 [enable|disable|refresh|status] [interface]"
            exit 1
            ;;
    esac
fi
