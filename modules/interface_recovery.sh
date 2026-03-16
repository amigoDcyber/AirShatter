#!/bin/bash
# =============================================================================
# AirShatter — modules/interface_recovery.sh
#
# Interface Recovery & Driver Refresh
#
# Uses functions from tools/airmonitor.sh:
#   airmonitor_disable()  → restore managed mode (airmon-ng / iw)
#   airmonitor_refresh()  → bring interface down then up
#   _restore_services()   → restart NetworkManager / wpa_supplicant
#
# Adds driver reload (modprobe -r / modprobe) which airmonitor.sh
# does not have — this is the step that fixes frozen/crashed drivers.
#
# Developer: amigoDcyber
# =============================================================================

# ─── Source airmonitor.sh ─────────────────────────────────────────────────────
_recovery_load_airmonitor() {
    local path="$AS_ROOT/tools/airmonitor.sh"
    if [[ ! -f "$path" ]]; then
        print_error "tools/airmonitor.sh not found: $path"
        return 1
    fi
    # shellcheck source=../tools/airmonitor.sh
    source "$path"
    return 0
}

# ─── Resolve which interface to recover ──────────────────────────────────────
_recovery_pick_interface() {
    # Try AirShatter globals first
    local candidates=("$MONITOR_IFACE" "$SELECTED_IFACE")
    for c in "${candidates[@]}"; do
        if [[ -n "$c" ]] && ip link show "$c" &>/dev/null 2>&1; then
            RECOVERY_IFACE="$c"
            print_info "Target interface: ${WHITE}$RECOVERY_IFACE${NC}"
            return 0
        fi
    done

    # Nothing pre-selected — ask user
    print_warning "No interface currently selected."
    echo

    if declare -f get_wireless_interfaces &>/dev/null; then
        local ifaces
        mapfile -t ifaces < <(get_wireless_interfaces)
        if [[ ${#ifaces[@]} -gt 0 ]]; then
            printf "  ${BCYAN}%-5s %-18s %-12s${NC}\n" "No." "Interface" "Mode"
            echo -e "  ${GRAY}$(printf '%.0s─' {1..38})${NC}"
            local i=1
            for iface in "${ifaces[@]}"; do
                local mode
                mode=$(iw dev "$iface" info 2>/dev/null | awk '/type/{print $2}')
                printf "  ${WHITE}[%-3s]${NC} ${BGREEN}%-18s${NC} ${CYAN}%-12s${NC}\n" \
                       "$i" "$iface" "${mode:-managed}"
                ((i++))
            done
            echo
            read -rp "$(echo -e "  ${BPURPLE}Select number or type name${NC}: ")" sel
            if [[ "$sel" =~ ^[0-9]+$ ]] && \
               (( sel >= 1 && sel <= ${#ifaces[@]} )); then
                RECOVERY_IFACE="${ifaces[$((sel-1))]}"
            elif ip link show "$sel" &>/dev/null 2>&1; then
                RECOVERY_IFACE="$sel"
            else
                print_error "Interface not found."
                return 1
            fi
        fi
    else
        read -rp "$(echo -e "  ${BPURPLE}Enter interface name (e.g. wlan0, wlan0mon)${NC}: ")" RECOVERY_IFACE
        if ! ip link show "$RECOVERY_IFACE" &>/dev/null 2>&1; then
            print_error "Interface '$RECOVERY_IFACE' not found."
            return 1
        fi
    fi

    print_success "Interface set: $RECOVERY_IFACE"
    return 0
}

# ─── Show interface state ─────────────────────────────────────────────────────
_recovery_show_status() {
    local iface="${1:-$RECOVERY_IFACE}"
    [[ -z "$iface" ]] && return

    # Wait briefly so kernel state is settled after changes
    sleep 1

    echo
    echo -e "  ${WHITE}Interface: ${BGREEN}$iface${NC}"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..40})${NC}"

    local mode mac state driver channel
    mode=$(iw dev "$iface" info 2>/dev/null | awk '/type/{print $2}')
    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null)
    driver=$(ethtool -i "$iface" 2>/dev/null | awk '/driver:/{print $2}')
    [[ -z "$driver" ]] && \
        driver=$(basename "$(readlink -f \
            "/sys/class/net/$iface/device/driver" 2>/dev/null)" 2>/dev/null)
    channel=$(iw dev "$iface" info 2>/dev/null | awk '/channel/{print $2}')

    printf "  ${CYAN}%-12s${NC} %s\n" "Mode:"    "${mode:-unknown}"
    printf "  ${CYAN}%-12s${NC} %s\n" "MAC:"     "${mac:-unknown}"
    printf "  ${CYAN}%-12s${NC} %s\n" "State:"   "${state:-unknown}"
    printf "  ${CYAN}%-12s${NC} %s\n" "Driver:"  "${driver:-unknown}"
    printf "  ${CYAN}%-12s${NC} %s\n" "Channel:" "${channel:--}"
    echo
}

# ─── Driver reload via modprobe ───────────────────────────────────────────────
# This is the step airmonitor.sh is missing — unloads and reloads the
# kernel Wi-Fi driver to clear frozen/crashed driver state.
_recovery_reload_driver() {
    local iface="$1"

    # Get driver name — try ethtool first, fallback to sysfs
    local driver
    driver=$(ethtool -i "$iface" 2>/dev/null | awk '/driver:/{print $2}')
    if [[ -z "$driver" ]]; then
        driver=$(basename "$(readlink -f \
            "/sys/class/net/$iface/device/driver" 2>/dev/null)" 2>/dev/null)
    fi

    if [[ -z "$driver" ]]; then
        print_warning "Could not detect driver for $iface — skipping module reload."
        return 0
    fi

    print_info "Driver detected: ${BYELLOW}$driver${NC}"
    print_info "Unloading module: $driver ..."
    modprobe -r "$driver" 2>/dev/null
    sleep 3

    print_info "Reloading module: $driver ..."
    modprobe "$driver" 2>/dev/null
    sleep 2

    print_success "Driver $driver reloaded."
    log_action "INTERFACE_RECOVERY" "Driver reload: modprobe -r $driver && modprobe $driver"
}

# ─── Full recovery sequence ───────────────────────────────────────────────────
_recovery_run() {
    local iface="$1"

    # Step 1 — bring interface down
    print_section "Step 1 — Bring Interface Down"
    print_info "ip link set $iface down"
    ip link set "$iface" down 2>/dev/null
    sleep 1
    print_success "Interface down."

    # Step 2 — force managed mode via airmonitor_disable()
    print_section "Step 2 — Restore Managed Mode"
    print_info "Calling airmonitor_disable() from airmonitor.sh..."
    airmonitor_disable "$iface"

    # Step 3 — unload and reload the kernel driver
    print_section "Step 3 — Reload Kernel Driver"
    _recovery_reload_driver "$iface"

    # After driver reload the interface may have been renamed back
    # e.g. wlan0mon → wlan0. Find the new name.
    local base_iface="${iface%mon}"
    local active_iface="$iface"
    if ip link show "$base_iface" &>/dev/null 2>&1; then
        active_iface="$base_iface"
    fi

    # Step 4 — bring interface back up via airmonitor_refresh()
    print_section "Step 4 — Bring Interface Back Up"
    print_info "Calling airmonitor_refresh() from airmonitor.sh..."
    airmonitor_refresh "$active_iface"

    # Step 5 — restart network services via _restore_services()
    print_section "Step 5 — Restart Network Services"
    print_info "Calling _restore_services() from airmonitor.sh..."
    _restore_services

    # Update AirShatter globals
    SELECTED_IFACE="$active_iface"
    MONITOR_IFACE=""

    log_success "Full recovery complete. Interface=$active_iface"
    return 0
}

# ─── Module entry point ───────────────────────────────────────────────────────
module_interface_recovery() {
    print_section "Interface Recovery & Driver Refresh"
    log_separator
    log_action "MODULE" "interface_recovery — entry"

    # Load airmonitor.sh functions
    _recovery_load_airmonitor || { pause; return 1; }

    # Resolve target interface
    _recovery_pick_interface   || { pause; return 1; }

    # Show state before
    print_info "State BEFORE recovery:"
    _recovery_show_status "$RECOVERY_IFACE"

    # What will happen
    echo -e "  ${BYELLOW}Recovery steps:${NC}"
    echo -e "  ${GRAY}  1. ip link set $RECOVERY_IFACE down${NC}"
    echo -e "  ${GRAY}  2. airmonitor_disable()  — restore managed mode${NC}"
    echo -e "  ${GRAY}  3. modprobe -r / modprobe — reload kernel driver${NC}"
    echo -e "  ${GRAY}  4. airmonitor_refresh()  — bring interface back up${NC}"
    echo -e "  ${GRAY}  5. _restore_services()   — restart NetworkManager${NC}"
    echo

    confirm "Run full recovery on $RECOVERY_IFACE?" || {
        print_info "Cancelled."
        log_action "INTERFACE_RECOVERY" "User cancelled"
        return 0
    }

    echo
    _recovery_run "$RECOVERY_IFACE"

    # Show state after
    print_info "State AFTER recovery:"
    _recovery_show_status "$SELECTED_IFACE"

    print_success "Done. Interface is back in managed mode."
    print_info "Select interface again (Menu option 1) before continuing."
}
