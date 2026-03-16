#!/bin/bash
# =============================================================================
# AirShatter — modules/analyzer.sh
# Capture file inspection and traffic analysis
# Developer: amigoDcyber
# =============================================================================

# ─── Analyze capture with hcxpcapngtool ───────────────────────────────────────
_analyze_hcx() {
    local file="$1"
    require_tool "hcxpcapngtool" || return 1

    print_info "Running hcxpcapngtool analysis..."
    echo -e "  ${GRAY}$(printf '%.0s─' {1..60})${NC}"
    hcxpcapngtool --info "$file" 2>/dev/null || \
        hcxpcapngtool -I "$file" 2>/dev/null || \
        print_warning "hcxpcapngtool info flag not supported on this version."
    echo -e "  ${GRAY}$(printf '%.0s─' {1..60})${NC}"
}

# ─── Handshake count check ────────────────────────────────────────────────────
_check_handshakes() {
    local file="$1"
    local tmp="/tmp/as_hs_check_$$"

    require_tool "hcxpcapngtool" || return 1

    hcxpcapngtool -o "$tmp.hc22000" "$file" 2>/dev/null

    if [[ -f "$tmp.hc22000" && -s "$tmp.hc22000" ]]; then
        local count
        count=$(wc -l < "$tmp.hc22000")
        print_success "Found $count EAPOL handshake hash(es) suitable for analysis"
        rm -f "$tmp.hc22000"
        return 0
    else
        print_warning "No complete WPA handshakes extracted from this file."
        rm -f "$tmp.hc22000"
        return 1
    fi
}

# ─── aircrack-ng summary ──────────────────────────────────────────────────────
_analyze_aircrack() {
    local file="$1"
    require_tool "aircrack-ng" || return 1

    print_info "Running aircrack-ng network summary..."
    echo
    # -J /dev/null prevents writing, just shows the AP list
    aircrack-ng "$file" 2>/dev/null | head -40
}

# ─── tshark / tcpdump fallback ────────────────────────────────────────────────
_analyze_tshark() {
    local file="$1"

    if command -v tshark &>/dev/null; then
        print_info "Running tshark summary..."
        echo
        tshark -r "$file" -q -z io,stat,0 2>/dev/null
        echo
        tshark -r "$file" -q -z wlan,stat 2>/dev/null || true
    elif command -v tcpdump &>/dev/null; then
        print_info "Running tcpdump summary (first 30 packets)..."
        echo
        tcpdump -r "$file" -c 30 2>/dev/null
    else
        print_warning "Neither tshark nor tcpdump found. Install one for deeper analysis."
    fi
}

# ─── Open in Wireshark ────────────────────────────────────────────────────────
_open_wireshark() {
    local file="$1"

    if command -v wireshark &>/dev/null; then
        print_info "Opening in Wireshark..."
        wireshark "$file" &>/dev/null &
        print_success "Wireshark launched (PID $!)"
    else
        print_warning "Wireshark not installed."
        print_info "Install: $(install_hint wireshark)"
    fi
}

# ─── File metadata ────────────────────────────────────────────────────────────
_show_file_info() {
    local file="$1"
    local size date name
    size=$(du -sh "$file" 2>/dev/null | cut -f1)
    date=$(stat -c '%y' "$file" 2>/dev/null | cut -d. -f1)
    name=$(basename "$file")

    echo
    echo -e "  ${WHITE}File      :${NC} $name"
    echo -e "  ${WHITE}Path      :${NC} $file"
    echo -e "  ${WHITE}Size      :${NC} $size"
    echo -e "  ${WHITE}Modified  :${NC} $date"
    echo
}

# ─── Main analyzer entry point ────────────────────────────────────────────────
module_analyze_capture() {
    print_section "Analyze Capture File"

    # File selection
    pick_capture_file || { pause; return 1; }

    local file="$SELECTED_CAPTURE"
    _show_file_info "$file"

    echo -e "  ${WHITE}Choose analysis type:${NC}"
    echo
    echo -e "  ${BGREEN}[1]${NC} ${WHITE}Full summary${NC}        ${GRAY}(hcxpcapngtool + aircrack-ng)${NC}"
    echo -e "  ${BGREEN}[2]${NC} ${WHITE}Handshake check${NC}     ${GRAY}(how many valid EAPOL pairs)${NC}"
    echo -e "  ${BGREEN}[3]${NC} ${WHITE}Traffic summary${NC}     ${GRAY}(tshark / tcpdump)${NC}"
    echo -e "  ${BGREEN}[4]${NC} ${WHITE}Open in Wireshark${NC}"
    echo -e "  ${BGREEN}[5]${NC} ${WHITE}All of the above${NC}"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Choice [1-5]${NC}: ")" ana_choice

    log_action "ANALYZE" "File=$file Choice=$ana_choice"

    echo

    case "$ana_choice" in
        1)
            print_section "hcxpcapngtool Analysis"
            _analyze_hcx "$file"
            echo
            print_section "Aircrack-ng Network Summary"
            _analyze_aircrack "$file"
            ;;
        2)
            print_section "Handshake Extraction Check"
            _check_handshakes "$file"
            ;;
        3)
            print_section "Traffic Summary"
            _analyze_tshark "$file"
            ;;
        4)
            _open_wireshark "$file"
            ;;
        5)
            print_section "hcxpcapngtool Analysis"
            _analyze_hcx "$file"
            echo
            print_section "Handshake Check"
            _check_handshakes "$file"
            echo
            print_section "Aircrack-ng Network Summary"
            _analyze_aircrack "$file"
            echo
            print_section "Traffic Summary"
            _analyze_tshark "$file"
            echo
            print_info "Open in Wireshark?"
            confirm "Launch Wireshark?" && _open_wireshark "$file"
            ;;
        *)
            print_error "Invalid choice."
            ;;
    esac

    log_success "Analysis complete for: $(basename "$file")"
}
