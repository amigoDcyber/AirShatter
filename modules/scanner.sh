#!/bin/bash
# =============================================================================
# AirShatter — modules/scanner.sh
# Extended multi-band network discovery
# Developer: amigoDcyber
# Supports: 2.4GHz (ch 1-14), 5GHz (ch 36-165), 6GHz (ch 1-233)
# =============================================================================

# ─── Terminal helper fallback ─────────────────────────────────────────────────
# Centralized terminal helper is now in core/colors.sh as _run_external_terminal.
_run_in_xterm() {
    local title="$1"; shift
    local term
    term=$(get_best_terminal)

    if [[ -n "$term" ]]; then
        # Launch asynchronously in xterm/uxterm so the user can see it
        # and then close it when ready.
        _run_external_terminal "$title" "$@" > /dev/null
        print_info "Scanning in a new window. Return here after closing it."
        pause
    else
        # Fallback to current terminal (synchronous)
        print_warning "xterm not found — running in current terminal."
        print_info "Press Ctrl+C when done scanning."
        echo
        "$@"
    fi
}

# ─── Detect which channels the adapter supports ───────────────────────────────
# Returns a sorted list of supported channel numbers via stdout
get_supported_channels() {
    local iface="${1:-$SELECTED_IFACE}"
    local phy

    # Get the phy name for this interface
    phy=$(iw dev "$iface" info 2>/dev/null | awk '/wiphy/{print "phy"$2}')
    if [[ -z "$phy" ]]; then
        # fallback: try phy0
        phy="phy0"
    fi

    # iw phy <phy> info lists every supported channel with its frequency
    # Example line: "* 2412 MHz [1] (20.0 dBm)"
    iw phy "$phy" info 2>/dev/null \
        | awk '/MHz \[/{
            # Extract channel number inside brackets
            match($0, /\[([0-9]+)\]/, arr)
            if (arr[1] != "") print arr[1]
        }' \
        | sort -n \
        | uniq
}

# ─── Convert frequency to band label ─────────────────────────────────────────
_freq_to_band() {
    local freq="$1"
    if   (( freq >= 2412 && freq <= 2484 )); then echo "2.4GHz"
    elif (( freq >= 5160 && freq <= 5885 )); then echo "5GHz"
    elif (( freq >= 5925 && freq <= 7125 )); then echo "6GHz"
    else echo "${freq}MHz"
    fi
}

# ─── Convert channel number to approximate frequency ─────────────────────────
_ch_to_freq() {
    local ch="$1"
    if   (( ch >= 1   && ch <= 13  )); then echo $(( 2407 + ch * 5 ))
    elif (( ch == 14                )); then echo 2484
    elif (( ch >= 36  && ch <= 64  )); then echo $(( 5000 + ch * 5 ))
    elif (( ch >= 100 && ch <= 165 )); then echo $(( 5000 + ch * 5 ))
    elif (( ch >= 1   && ch <= 233 )); then echo $(( 5950 + (ch - 1) * 5 ))  # 6GHz estimate
    else echo "?"
    fi
}

# ─── Print the scan results table header ─────────────────────────────────────
_print_scan_header() {
    echo
    printf "  ${BCYAN}%-32s %-19s %-5s %-8s %-10s %-7s${NC}\n" \
           "SSID" "BSSID" "CH" "Freq" "Encryption" "Signal"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..86})${NC}"
}

# ─── Print one result row with color coding ───────────────────────────────────
_print_scan_row() {
    local ssid="$1" bssid="$2" ch="$3" freq="$4" enc="$5" signal="$6"

    # Color-code encryption
    local enc_color="$GREEN"
    case "${enc^^}" in
        *WPA3*)  enc_color="$BGREEN"  ;;
        *WPA2*)  enc_color="$CYAN"    ;;
        *WPA*)   enc_color="$YELLOW"  ;;
        *WEP*)   enc_color="$BRED"    ;;
        *OPEN*)  enc_color="$RED"     ;;
    esac

    # Color-code signal strength
    local sig_color="$GREEN"
    local sig_num
    sig_num=$(echo "$signal" | tr -dc '0-9\-')
    if   (( sig_num < -80 )); then sig_color="$RED"
    elif (( sig_num < -70 )); then sig_color="$YELLOW"
    fi

    printf "  ${WHITE}%-32s${NC} ${GRAY}%-19s${NC} ${BCYAN}%-5s${NC} ${GRAY}%-8s${NC} ${enc_color}%-10s${NC} ${sig_color}%-7s${NC}\n" \
           "${ssid:0:31}" "$bssid" "$ch" "$freq" "${enc:-Open}" "${signal:--}"
}

# ─── iw scan: passive scan (no monitor needed), all detected APs ──────────────
_scan_with_iw() {
    local iface="$1"
    local supported_chs=()
    mapfile -t supported_chs < <(get_supported_channels "$iface")

    print_info "Detected ${#supported_chs[@]} supported channels on $(get_iface_driver "$iface")"

    # Group channels by band for display
    local chs_24=() chs_5=() chs_6=()
    for ch in "${supported_chs[@]}"; do
        if   (( ch <= 14  )); then chs_24+=("$ch")
        elif (( ch <= 177 )); then chs_5+=("$ch")
        else                       chs_6+=("$ch")
        fi
    done
    [[ ${#chs_24[@]} -gt 0 ]] && print_info "  2.4GHz channels: ${chs_24[*]}"
    [[ ${#chs_5[@]}  -gt 0 ]] && print_info "  5GHz channels  : ${chs_5[*]}"
    [[ ${#chs_6[@]}  -gt 0 ]] && print_info "  6GHz channels  : ${chs_6[*]}"

    echo
    print_info "Running iw scan (may take 5-15s)..."

    local scan_out
    scan_out=$(iw dev "$iface" scan 2>/dev/null)

    if [[ -z "$scan_out" ]]; then
        print_warning "iw scan returned no results."
        print_info "The adapter may be busy. Try bringing it up: ip link set $iface up"
        return 1
    fi

    _print_scan_header

    # ── Parse iw scan output ──────────────────────────────────────────────────
    # iw scan outputs one block per BSS starting with "BSS xx:xx:xx..."
    # We accumulate fields then print when we hit the next BSS or EOF.
    local ssid="" bssid="" channel="" freq="" signal="" enc=""
    local ap_count=0

    _flush_iw_entry() {
        [[ -z "$bssid" ]] && return
        local band
        band=$(_freq_to_band "${freq:-0}")
        _print_scan_row "$ssid" "$bssid" "$channel" "${freq:--}MHz/$band" "$enc" "$signal"
        log_info "SCAN_IW SSID=${ssid:-(hidden)} BSSID=$bssid CH=$channel FREQ=$freq ENC=$enc SIG=$signal"
        ((ap_count++))
    }

    while IFS= read -r line; do
        if [[ "$line" =~ ^BSS[[:space:]]([0-9a-fA-F:]{17}) ]]; then
            _flush_iw_entry
            bssid="${BASH_REMATCH[1]}"
            ssid=""; channel=""; freq=""; signal=""; enc=""
        elif [[ "$line" =~ SSID:[[:space:]]+(.*) ]]; then
            ssid="${BASH_REMATCH[1]}"
            # Blank SSID = hidden network
            [[ -z "${ssid// }" ]] && ssid="(hidden)"
        elif [[ "$line" =~ freq:[[:space:]]+([0-9]+) ]]; then
            freq="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ DS[[:space:]]Parameter.*channel[[:space:]]+([0-9]+) ]]; then
            channel="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \*[[:space:]]primary[[:space:]]channel:[[:space:]]+([0-9]+) ]]; then
            channel="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ signal:[[:space:]]+([0-9\.\-]+) ]]; then
            signal="${BASH_REMATCH[1]} dBm"
        elif [[ "$line" =~ RSN: ]];      then enc="WPA2"
        elif [[ "$line" =~ WPA:[[:space:]] ]]; then [[ "$enc" != "WPA2" ]] && enc="WPA"
        elif [[ "$line" =~ WPA3 ]];      then enc="WPA3"
        elif [[ "$line" =~ Privacy ]];   then [[ -z "$enc" ]] && enc="WEP/Priv"
        fi
    done <<< "$scan_out"
    _flush_iw_entry  # flush last entry

    echo
    print_success "Found $ap_count access point(s)"
    log_action "SCAN_IW" "Interface=$iface APs_found=$ap_count"
}

# ─── airodump-ng full scan in xterm, all bands ────────────────────────────────
_scan_with_airodump() {
    local mon_iface="$1"
    local band_opt=""
    local out_prefix="/tmp/as_scan_$$"

    # Detect 5GHz/6GHz support and build --band flag
    local supported_chs=()
    mapfile -t supported_chs < <(get_supported_channels "$SELECTED_IFACE" 2>/dev/null)

    local has_5ghz=false has_6ghz=false
    for ch in "${supported_chs[@]}"; do
        (( ch >= 36 && ch <= 177 )) && has_5ghz=true
        (( ch >= 183           ))   && has_6ghz=true
    done

    if [[ "$has_6ghz" == true ]]; then
        band_opt="abg"
        print_info "Adapter supports 6GHz — scanning all bands (2.4/5/6GHz)"
    elif [[ "$has_5ghz" == true ]]; then
        band_opt="abg"
        print_info "Adapter supports 5GHz — scanning 2.4GHz + 5GHz"
    else
        band_opt="bg"
        print_info "Adapter is 2.4GHz only — scanning 2.4GHz channels"
    fi

    echo
    print_info "Launching airodump-ng in xterm. Close window when done."
    print_info "Output prefix: ${out_prefix}"
    echo

    local cmd=(
        airodump-ng
        --band "$band_opt"
        --write "$out_prefix"
        --output-format csv,pcap
        "$mon_iface"
    )

    _run_in_xterm "AirShatter — Network Scan [$mon_iface] [$band_opt]" "${cmd[@]}"

    # ── Parse CSV results ─────────────────────────────────────────────────────
    local csv_file="${out_prefix}-01.csv"
    if [[ ! -f "$csv_file" ]]; then
        print_warning "No CSV output found. Scan may have been cancelled before writing."
        return 1
    fi

    echo
    print_section "Scan Results"
    _print_scan_header

    local ap_count=0
    local in_stations=false

    while IFS=',' read -r bssid first_seen last_seen channel speed \
                          privacy cipher auth power beacons iv \
                          lanip id_len essid key; do

        # CSV has two sections separated by blank line; second section = Stations
        [[ "$bssid" =~ ^[[:space:]]*Station ]] && { in_stations=true; continue; }
        $in_stations && continue

        # Skip header row and blank lines
        [[ "$bssid" =~ ^[[:space:]]*BSSID ]] && continue
        [[ -z "${bssid// }" ]] && continue

        local cb ce ch cp cs
        cb="${bssid// /}"
        [[ -z "$cb" || "$cb" == "BSSID" ]] && continue

        ce="${essid// /}"
        ch="${channel// /}"
        cp="${privacy// /}"
        cs="${power// /}"

        # Derive approximate frequency from channel
        local freq band cf
        cf=$(_ch_to_freq "$ch")
        band=$(_freq_to_band "${cf:-0}")

        _print_scan_row "${ce:-(hidden)}" "$cb" "$ch" "${cf}MHz/$band" "${cp:-Open}" "${cs:--}"
        log_info "SCAN_AIRODUMP SSID=${ce} BSSID=${cb} CH=${ch} ENC=${cp} PWR=${cs}"
        ((ap_count++))

    done < "$csv_file"

    echo
    print_success "Found $ap_count access point(s)"

    # Save CSV to logs/
    local log_out="$AS_ROOT/logs/scan_$(date +%Y%m%d_%H%M%S).csv"
    cp "$csv_file" "$log_out" 2>/dev/null
    print_success "Raw scan data saved → $log_out"
    log_action "SCAN_AIRODUMP" "Interface=$mon_iface Band=$band_opt APs=$ap_count Saved=$log_out"

    rm -f "${out_prefix}"* 2>/dev/null
}

# ─── Module entry point ───────────────────────────────────────────────────────
module_scan_networks() {
    print_section "Scan Nearby Networks"
    log_separator
    log_action "MODULE" "scanner — entry"

    require_interface || { pause; return 1; }

    echo -e "  ${CYAN}Selected interface :${NC} ${WHITE}$SELECTED_IFACE${NC}"
    local driver
    driver=$(get_iface_driver "$SELECTED_IFACE")
    echo -e "  ${CYAN}Driver             :${NC} ${WHITE}$driver${NC}"
    echo

    echo -e "  ${WHITE}[1]${NC} Quick scan    ${GRAY}(iw scan — managed mode, multi-band)${NC}"
    echo -e "  ${WHITE}[2]${NC} Full scan     ${GRAY}(airodump-ng — requires monitor mode, multi-band)${NC}"
    echo -e "  ${WHITE}[0]${NC} Back"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Choice [0-2]${NC}: ")" scan_choice

    case "$scan_choice" in
        1)
            echo
            _scan_with_iw "$SELECTED_IFACE"
            ;;
        2)
            require_monitor_mode || {
                echo
                print_info "Enable monitor mode first — Menu option 2."
                pause
                return 1
            }
            echo
            _scan_with_airodump "$MONITOR_IFACE"
            ;;
        0) return 0 ;;
        *)
            print_error "Invalid choice: '$scan_choice'"
            ;;
    esac
}
