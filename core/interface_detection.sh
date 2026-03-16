#!/bin/bash
# =============================================================================
# AirShatter — core/interface_detection.sh
# Wireless interface detection and selection
# Developer: amigoDcyber
# =============================================================================

# Global: set by select_interface(), used by all modules
SELECTED_IFACE=""
MONITOR_IFACE=""

# ─── List all wireless interfaces ─────────────────────────────────────────────
get_wireless_interfaces() {
    # Returns array of wireless interfaces found on the system
    local ifaces=()

    # Primary method: iw dev
    if command -v iw &>/dev/null; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*Interface[[:space:]]+(.*) ]]; then
                ifaces+=("${BASH_REMATCH[1]}")
            fi
        done < <(iw dev 2>/dev/null)
    fi

    # Fallback: /sys/class/net — check for wireless symlink
    if [[ ${#ifaces[@]} -eq 0 ]]; then
        for iface in /sys/class/net/*/; do
            local name
            name=$(basename "$iface")
            if [[ -d "/sys/class/net/$name/wireless" ]]; then
                ifaces+=("$name")
            fi
        done
    fi

    # Deduplicate
    local -A seen
    local unique=()
    for i in "${ifaces[@]}"; do
        if [[ -z "${seen[$i]}" ]]; then
            seen[$i]=1
            unique+=("$i")
        fi
    done

    printf '%s\n' "${unique[@]}"
}

# ─── Get interface details ─────────────────────────────────────────────────────
get_iface_mode() {
    local iface="$1"
    iw dev "$iface" info 2>/dev/null | awk '/type/{print $2}'
}

get_iface_driver() {
    local iface="$1"
    local driver
    driver=$(readlink -f "/sys/class/net/$iface/device/driver" 2>/dev/null)
    basename "$driver" 2>/dev/null || echo "unknown"
}

get_iface_mac() {
    local iface="$1"
    cat "/sys/class/net/$iface/address" 2>/dev/null || ip link show "$iface" 2>/dev/null | awk '/ether/{print $2}'
}

get_iface_state() {
    local iface="$1"
    cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown"
}

# ─── Detect and display interfaces ────────────────────────────────────────────
detect_interfaces() {
    print_section "Wireless Interface Detection"

    local ifaces
    mapfile -t ifaces < <(get_wireless_interfaces)

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        print_error "No wireless interfaces detected."
        print_info "Make sure your Wi-Fi adapter is connected and drivers are loaded."
        log_warning "No wireless interfaces found during detection"
        return 1
    fi

    echo -e "  ${GRAY}Found ${#ifaces[@]} wireless interface(s):${NC}"
    echo

    printf "  ${BCYAN}%-5s %-15s %-12s %-20s %-10s${NC}\n" "No." "Interface" "Mode" "Driver" "State"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..60})${NC}"

    local i=1
    for iface in "${ifaces[@]}"; do
        local mode driver mac state
        mode=$(get_iface_mode "$iface")
        driver=$(get_iface_driver "$iface")
        state=$(get_iface_state "$iface")

        # Color by mode
        local mode_color="${GREEN}"
        [[ "$mode" == "monitor" ]] && mode_color="${BRED}"

        printf "  ${WHITE}%-5s${NC} ${BGREEN}%-15s${NC} ${mode_color}%-12s${NC} ${GRAY}%-20s %-10s${NC}\n" \
               "[$i]" "$iface" "${mode:-managed}" "${driver:0:18}" "$state"
        ((i++))
    done

    echo
    log_info "Detected interfaces: ${ifaces[*]}"
}

# ─── Interface selection prompt ────────────────────────────────────────────────
select_interface() {
    detect_interfaces || return 1

    local ifaces
    mapfile -t ifaces < <(get_wireless_interfaces)

    echo
    read -rp "$(echo -e "  ${BPURPLE}Select interface number (or type name directly)${NC}: ")" choice

    # If user typed a name directly
    if [[ "$choice" =~ ^[a-zA-Z] ]]; then
        # Validate it exists
        if ip link show "$choice" &>/dev/null; then
            SELECTED_IFACE="$choice"
        else
            print_error "Interface '$choice' not found."
            return 1
        fi
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ifaces[@]} )); then
        SELECTED_IFACE="${ifaces[$((choice-1))]}"
    else
        print_error "Invalid selection."
        return 1
    fi

    # Detect if already in monitor mode
    local mode
    mode=$(get_iface_mode "$SELECTED_IFACE")
    if [[ "$mode" == "monitor" ]]; then
        MONITOR_IFACE="$SELECTED_IFACE"
        print_success "Selected: $SELECTED_IFACE ${GRAY}(already in monitor mode)${NC}"
    else
        print_success "Selected: $SELECTED_IFACE ${GRAY}(mode: ${mode:-managed})${NC}"
        MONITOR_IFACE="${SELECTED_IFACE}mon"
    fi

    log_action "INTERFACE_SELECT" "Selected interface: $SELECTED_IFACE (mode: ${mode:-managed})"
    return 0
}

# ─── Require interface to be selected ─────────────────────────────────────────
require_interface() {
    if [[ -z "$SELECTED_IFACE" ]]; then
        print_warning "No interface selected. Please select one first (Menu option 1)."
        return 1
    fi
    return 0
}

# ─── Require monitor mode ─────────────────────────────────────────────────────
require_monitor_mode() {
    require_interface || return 1

    local mode
    mode=$(get_iface_mode "$SELECTED_IFACE" 2>/dev/null)

    # Also check for common mon suffix interfaces
    local mon_iface="${SELECTED_IFACE}mon"
    if [[ "$mode" == "monitor" ]]; then
        MONITOR_IFACE="$SELECTED_IFACE"
        return 0
    elif ip link show "$mon_iface" &>/dev/null 2>&1; then
        local mon_mode
        mon_mode=$(get_iface_mode "$mon_iface")
        if [[ "$mon_mode" == "monitor" ]]; then
            MONITOR_IFACE="$mon_iface"
            return 0
        fi
    fi

    print_warning "Monitor mode is not active."
    print_info "Enable monitor mode first (Menu option 2)."
    return 1
}
