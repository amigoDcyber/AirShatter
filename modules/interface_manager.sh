#!/bin/bash
# =============================================================================
# AirShatter — modules/interface_manager.sh
# Interface management module — wraps tools/airmonitor.sh
# Developer: amigoDcyber
# =============================================================================

# ─── Source airmonitor.sh from tools/ ─────────────────────────────────────────
_load_airmonitor() {
    local airmon_path="$AS_ROOT/tools/airmonitor.sh"
    if [[ ! -f "$airmon_path" ]]; then
        print_error "tools/airmonitor.sh not found at: $airmon_path"
        return 1
    fi
    # shellcheck source=../tools/airmonitor.sh
    source "$airmon_path"
}

# ─── Enable monitor mode (menu entry point) ───────────────────────────────────
module_enable_monitor() {
    print_section "Enable Monitor Mode"

    require_interface || { pause; return 1; }
    _load_airmonitor || { pause; return 1; }

    echo -e "  ${CYAN}Interface  :${NC} $SELECTED_IFACE"
    echo -e "  ${CYAN}Current mode:${NC} $(get_iface_mode "$SELECTED_IFACE" 2>/dev/null || echo managed)"
    echo

    if ! confirm "Enable monitor mode on $SELECTED_IFACE?"; then
        print_info "Cancelled."
        return 0
    fi

    echo
    airmonitor_enable "$SELECTED_IFACE"
    local rc=$?

    echo
    if [[ $rc -eq 0 ]]; then
        airmonitor_status "$MONITOR_IFACE"
        print_success "Monitor interface ready: $MONITOR_IFACE"
    else
        print_error "Monitor mode failed. Check that your adapter supports it."
        print_info "Try: iw list | grep -A 10 'Supported interface modes'"
    fi
}

# ─── Disable monitor mode / restore managed (menu entry point) ────────────────
module_restore_managed() {
    print_section "Restore Managed Mode"

    _load_airmonitor || { pause; return 1; }

    local target="${MONITOR_IFACE:-$SELECTED_IFACE}"

    if [[ -z "$target" ]]; then
        print_warning "No interface selected. Select one first (Menu option 1)."
        pause
        return 1
    fi

    echo -e "  ${CYAN}Target interface:${NC} $target"
    echo

    if ! confirm "Restore managed mode on $target?"; then
        print_info "Cancelled."
        return 0
    fi

    echo
    airmonitor_disable "$target"
    local rc=$?

    echo
    if [[ $rc -eq 0 ]]; then
        [[ -n "$SELECTED_IFACE" ]] && airmonitor_status "$SELECTED_IFACE"
        print_success "Network adapter restored to managed mode."
        print_info "NetworkManager and other services have been restarted."
    else
        print_error "Could not fully restore managed mode."
        print_info "Try manually: sudo ip link set $target down && sudo iw dev $target set type managed && sudo ip link set $target up"
    fi
}

# ─── Refresh interface (recovery) ─────────────────────────────────────────────
module_refresh_interface() {
    print_section "Refresh / Recover Interface"

    _load_airmonitor || { pause; return 1; }
    require_interface || { pause; return 1; }

    echo -e "  ${CYAN}Interface:${NC} $SELECTED_IFACE"
    echo

    airmonitor_refresh "$SELECTED_IFACE"
    airmonitor_status  "$SELECTED_IFACE"
}
