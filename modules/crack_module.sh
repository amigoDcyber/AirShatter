#!/bin/bash
# =============================================================================
# AirShatter — modules/crack_module.sh
# Handshake password strength auditing — wraps tools/cracker.sh
# Developer: amigoDcyber
# =============================================================================

# ─── Load cracker.sh functions without running its main() ─────────────────────
_load_cracker() {
    local cracker_path="$AS_ROOT/tools/cracker.sh"

    if [[ ! -f "$cracker_path" ]]; then
        print_error "tools/cracker.sh not found at: $cracker_path"
        return 1
    fi

    # cracker.sh runs main_menu at the bottom only when executed directly.
    # We source it here to get access to its functions.
    # Temporarily override the bottom guard so it doesn't auto-run.
    _CRACKER_SOURCED=1
    # shellcheck source=../tools/cracker.sh
    source "$cracker_path"
    return 0
}

# ─── Run cracker.sh standalone (full interactive mode) ────────────────────────
_launch_cracker_standalone() {
    local cracker_path="$AS_ROOT/tools/cracker.sh"
    local cap_file="${1:-}"

    if [[ ! -f "$cracker_path" ]]; then
        print_error "tools/cracker.sh not found."
        return 1
    fi

    chmod +x "$cracker_path"

    if [[ -n "$cap_file" ]]; then
        # Pre-set the capture file as env var so cracker can pick it up
        export AS_PRESELECTED_CAP="$cap_file"
    fi

    bash "$cracker_path"
    unset AS_PRESELECTED_CAP
}

# ─── Integrated crack flow (no re-launch needed) ──────────────────────────────
_run_crack_inline() {
    local file="$1"
    local temp_dir="/tmp/as_crack_$$"
    mkdir -p "$temp_dir"
    chmod 700 "$temp_dir"

    # Step 1: convert to hc22000
    print_section "Converting Capture"
    print_info "Running hcxpcapngtool..."

    local hc22000="$temp_dir/handshake.hc22000"
    hcxpcapngtool -o "$hc22000" "$file" 2>/dev/null

    if [[ ! -s "$hc22000" ]]; then
        print_error "No valid EAPOL handshakes found in: $(basename "$file")"
        echo
        print_info "Verify the capture contains a complete 4-way WPA handshake."
        print_info "Use 'Analyze Capture File' (Menu option 5) to check first."
        rm -rf "$temp_dir"
        return 1
    fi

    local count
    count=$(wc -l < "$hc22000")
    print_success "Found $count handshake hash(es)"

    # Step 2: wordlist selection
    local wordlist=""
    echo
    print_section "Wordlist Selection"
    echo -e "  ${WHITE}[1]${NC} rockyou.txt        ${GRAY}(/usr/share/wordlists/rockyou.txt)${NC}"
    echo -e "  ${WHITE}[2]${NC} Custom path"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Choice [1-2]${NC}: ")" wl_choice

    case "$wl_choice" in
        1)
            local rk="/usr/share/wordlists/rockyou.txt"
            local rk_gz="/usr/share/wordlists/rockyou.txt.gz"
            if [[ -f "$rk" ]]; then
                wordlist="$rk"
                print_success "Using rockyou.txt"
            elif [[ -f "$rk_gz" ]]; then
                print_info "Extracting rockyou.txt.gz..."
                gzip -dk "$rk_gz" 2>/dev/null && wordlist="$rk" || {
                    print_error "Extraction failed."
                    rm -rf "$temp_dir"
                    return 1
                }
            else
                print_error "rockyou.txt not found. Try option 2."
                rm -rf "$temp_dir"
                return 1
            fi
            ;;
        2)
            read -rp "$(echo -e "  ${BPURPLE}Wordlist path${NC}: ")" wordlist
            wordlist="${wordlist/#\~/$HOME}"
            if [[ ! -f "$wordlist" ]]; then
                print_error "File not found: $wordlist"
                rm -rf "$temp_dir"
                return 1
            fi
            local wc_count
            wc_count=$(wc -l < "$wordlist")
            print_success "Wordlist: $wordlist ($wc_count words)"
            ;;
        *)
            print_error "Invalid choice."
            rm -rf "$temp_dir"
            return 1
            ;;
    esac

    # Step 3: launch hashcat
    local pot="$temp_dir/crack.pot"
    local out_dir="$AS_ROOT/logs"
    mkdir -p "$out_dir"
    local output="$out_dir/crack_$(basename "$file")_$(date +%Y%m%d_%H%M%S).txt"

    print_section "Launching Hashcat"
    print_info "Mode     : 22000 (WPA-PBKDF2-PMKID+EAPOL)"
    print_info "Target   : $(basename "$file")"
    print_info "Wordlist : $(basename "$wordlist")"
    print_info "Potfile  : $pot"
    echo
    print_warning "Note: --force is NOT used. Corrupted handshakes will be skipped."
    echo

    log_action "CRACK_START" "File=$(basename "$file") Wordlist=$(basename "$wordlist")"

    hashcat -m 22000 "$hc22000" "$wordlist" \
        --hwmon-disable \
        --quiet \
        --potfile-path "$pot" \
        --status \
        --status-timer=10 \
        2>/dev/null

    echo
    # Step 4: show results
    if hashcat -m 22000 "$hc22000" --show --potfile-path "$pot" --quiet 2>/dev/null | grep -q ":"; then
        hashcat -m 22000 "$hc22000" --show --potfile-path "$pot" --quiet 2>/dev/null > "$output"

        echo -e "  ${BGREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "  ${BGREEN}║       🔓  HANDSHAKE CRACKED!             ║${NC}"
        echo -e "  ${BGREEN}╚══════════════════════════════════════════╝${NC}"
        echo

        declare -A seen_crack
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local ssid password key
            ssid=$(echo "$line"     | awk -F: '{print $(NF-1)}')
            password=$(echo "$line" | awk -F: '{print $NF}')
            key="${ssid}:${password}"
            [[ -n "${seen_crack[$key]}" ]] && continue
            seen_crack[$key]=1
            echo -e "  ${WHITE}SSID    :${NC} ${BCYAN}$ssid${NC}"
            echo -e "  ${WHITE}Password:${NC} ${BGREEN}$password${NC}"
            echo -e "  ${GRAY}  ────────────────────────────────────────${NC}"
        done < "$output"
        unset seen_crack

        echo
        print_success "Results saved → $output"
        log_success "CRACK_SUCCESS: $(basename "$file") → results in $output"
    else
        echo -e "  ${BRED}╔══════════════════════════════════════════╗${NC}"
        echo -e "  ${BRED}║    ✗  Password not found in wordlist     ║${NC}"
        echo -e "  ${BRED}╚══════════════════════════════════════════╝${NC}"
        echo
        print_info "Suggestions:"
        echo -e "${GRAY}    • Try a larger wordlist (e.g. rockyou, darkweb2017)${NC}"
        echo -e "${GRAY}    • Add rules: hashcat -m 22000 $hc22000 $wordlist -r /usr/share/hashcat/rules/best64.rule${NC}"
        echo -e "${GRAY}    • Brute force 8-digit: hashcat -m 22000 $hc22000 -a 3 ?d?d?d?d?d?d?d?d${NC}"
        log_warning "CRACK_NOT_FOUND: $(basename "$file")"
    fi

    rm -rf "$temp_dir"
}

# ─── Main crack module entry point ────────────────────────────────────────────
module_audit_password() {
    print_section "Audit Handshake Password Strength"

    require_tool "hashcat"        || { pause; return 1; }
    require_tool "hcxpcapngtool" || { pause; return 1; }

    echo
    echo -e "  ${WHITE}[1]${NC} Select capture file and audit inline"
    echo -e "  ${WHITE}[2]${NC} Launch full cracker.sh interactive session"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Choice [1-2]${NC}: ")" mode_choice

    case "$mode_choice" in
        1)
            echo
            pick_capture_file || { pause; return 1; }
            local file="$SELECTED_CAPTURE"
            echo
            print_info "Selected: $(basename "$file")"
            echo
            _run_crack_inline "$file"
            ;;
        2)
            echo
            print_info "Launching cracker.sh interactive session..."
            sleep 1
            _launch_cracker_standalone
            ;;
        *)
            print_error "Invalid choice."
            ;;
    esac
}
