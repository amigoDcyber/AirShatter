#!/bin/bash
# cracker.sh - Wi-Fi Handshake Password Recovery
# Developer: amigoDcyber
# Version 3.1 - Wi-Fi Only
# ==========================================

# ==========================================
# COLORS
# ==========================================
RED='\033[0;31m'
BRED='\033[1;31m'
GREEN='\033[0;32m'
BGREEN='\033[1;32m'
YELLOW='\033[0;33m'
BYELLOW='\033[1;33m'
CYAN='\033[0;36m'
BCYAN='\033[1;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
BPURPLE='\033[1;35m'
GRAY='\033[0;90m'
NC='\033[0m'

# ==========================================
# GLOBALS
# ==========================================
CRACK_DIR="$HOME/cracked"
TEMP_DIR="/tmp/cracker_$$"
WORDLIST=""
TARGET_FILE=""
VERSION="3.1"

# ==========================================
# BANNER
# ==========================================
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
    echo -e "${BCYAN}        ⚡  Amigo Cyber — Wi-Fi Handshake Cracker v${VERSION}  ⚡${NC}"
    echo -e "${GRAY}              Developer: ${BGREEN}amigoDcyber${NC}"
    echo -e "${BRED}           ═════════════════════════════════════════════${NC}"
    echo
}

# ==========================================
# PRINT HELPERS
# ==========================================
print_status()   { echo -e "${BGREEN}[${WHITE}+${BGREEN}]${NC} ${WHITE}$1${NC}"; }
print_info()     { echo -e "${BCYAN}[${WHITE}*${BCYAN}]${NC} ${CYAN}$1${NC}"; }
print_error()    { echo -e "${BRED}[${WHITE}-${BRED}]${NC} ${RED}$1${NC}"; }
print_warning()  { echo -e "${BYELLOW}[${WHITE}!${BYELLOW}]${NC} ${YELLOW}$1${NC}"; }
print_question() { echo -e "${BPURPLE}[${WHITE}?${BPURPLE}]${NC} ${PURPLE}$1${NC}"; }
print_success()  { echo -e "${BGREEN}[${WHITE}✓${BGREEN}]${NC} ${BGREEN}$1${NC}"; }
print_section()  {
    echo
    echo -e "${BCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  $1${NC}"
    echo -e "${BCYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pause() {
    echo
    read -p "$(echo -e "${GRAY}  Press Enter to continue...${NC}")"
}

# ==========================================
# SETUP & CLEANUP
# ==========================================
setup_dirs() {
    mkdir -p "$CRACK_DIR" 2>/dev/null || {
        print_error "Cannot create crack dir: $CRACK_DIR"
        exit 1
    }
    mkdir -p "$TEMP_DIR" 2>/dev/null || {
        print_error "Cannot create temp dir: $TEMP_DIR"
        exit 1
    }
    chmod 700 "$TEMP_DIR"
}

cleanup() {
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

trap cleanup EXIT INT TERM

# ==========================================
# DEPENDENCY CHECK
# ==========================================
check_deps() {
    print_section "Checking Dependencies"
    local missing=()
    local tools=("hashcat" "hcxpcapngtool")

    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            print_success "$tool found → $(command -v "$tool")"
        else
            print_warning "$tool NOT found"
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
        print_error "Missing required tools: ${missing[*]}"
        echo
        if [[ -f /etc/arch-release ]]; then
            echo -e "${WHITE}  sudo pacman -S hashcat hcxtools${NC}"
        elif [[ -f /etc/debian_version ]]; then
            echo -e "${WHITE}  sudo apt install hashcat hcxtools${NC}"
        else
            print_info "Please install the missing tools manually."
        fi
        echo
        exit 1
    fi

    print_success "All dependencies ready!"
    sleep 1
}

# ==========================================
# WORDLIST SELECTION
# ==========================================
choose_wordlist() {
    echo
    print_section "Wordlist Selection"
    echo -e "  ${WHITE}[1]${NC} rockyou.txt ${GRAY}(default)${NC}"
    echo -e "  ${WHITE}[2]${NC} Custom path"
    echo
    read -p "$(echo -e "  ${BPURPLE}Choice [1-2]${NC}: ")" wl_choice

    case "$wl_choice" in
        1)
            local rk="/usr/share/wordlists/rockyou.txt"
            local rk_gz="/usr/share/wordlists/rockyou.txt.gz"
            if [[ -f "$rk" ]]; then
                WORDLIST="$rk"
                print_success "Using rockyou.txt"
            elif [[ -f "$rk_gz" ]]; then
                print_info "Extracting rockyou.txt.gz..."
                sudo gzip -dk "$rk_gz" 2>/dev/null && WORDLIST="$rk" || {
                    print_error "Failed to extract rockyou.txt.gz"
                    return 1
                }
                print_success "rockyou.txt extracted and ready"
            else
                print_error "rockyou.txt not found!"
                print_info "Install with: sudo apt install wordlists"
                return 1
            fi
            ;;
        2)
            read -p "$(echo -e "  ${BPURPLE}Wordlist path${NC}: ")" WORDLIST
            WORDLIST="${WORDLIST/#\~/$HOME}"
            if [[ ! -f "$WORDLIST" ]]; then
                print_error "File not found: $WORDLIST"
                return 1
            fi
            local wc
            wc=$(wc -l < "$WORDLIST" 2>/dev/null)
            print_success "Using: $WORDLIST (${wc} words)"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
}

# ==========================================
# TARGET FILE PROMPT
# ==========================================
prompt_target_file() {
    echo
    print_question "Path to capture file (.cap / .pcap / .pcapng):"
    read -p "  Path: " TARGET_FILE
    TARGET_FILE="${TARGET_FILE/#\~/$HOME}"

    if [[ -z "$TARGET_FILE" ]]; then
        print_error "No path entered."
        return 1
    fi
    if [[ ! -f "$TARGET_FILE" ]]; then
        print_error "File not found: $TARGET_FILE"
        print_info "Double-check the path and try again."
        return 1
    fi

    local ext="${TARGET_FILE##*.}"
    if [[ "$ext" != "cap" && "$ext" != "pcap" && "$ext" != "pcapng" ]]; then
        print_warning "Unexpected extension '.$ext' — expected .cap / .pcap / .pcapng"
        read -p "$(echo -e "  ${BPURPLE}Continue anyway? [y/N]${NC}: ")" ans
        [[ "${ans,,}" != "y" ]] && return 1
    fi

    print_success "Target set: $TARGET_FILE"
    return 0
}

# ==========================================
# CRACK WI-FI HANDSHAKE
# ==========================================
crack_handshake() {
    local file="$1"
    local hc22000="$TEMP_DIR/handshake.hc22000"
    local pot="$TEMP_DIR/wpa.pot"
    local output="$CRACK_DIR/wpa_$(basename "$file")_$(date +%Y%m%d_%H%M%S).txt"

    print_section "Converting Capture → hc22000"
    print_info "Running hcxpcapngtool..."

    if ! hcxpcapngtool -o "$hc22000" "$file" 2>/dev/null; then
        print_error "Conversion failed!"
        print_info "Verify the file: hcxpcapngtool --info \"$file\""
        return 1
    fi

    if [[ ! -s "$hc22000" ]]; then
        print_error "No valid WPA handshakes found in capture."
        echo
        print_info "Possible reasons:"
        echo -e "${GRAY}  • No complete 4-way handshake in capture${NC}"
        echo -e "${GRAY}  • Client never authenticated during capture${NC}"
        echo -e "${GRAY}  • Capture too short — try capturing longer${NC}"
        return 1
    fi

    local count
    count=$(wc -l < "$hc22000")
    print_success "Found ${count} handshake hash(es)"

    choose_wordlist || return 1

    print_section "Launching Hashcat"
    print_info "Mode     : 22000 (WPA/WPA2)"
    print_info "Wordlist : $(basename "$WORDLIST")"
    print_info "Potfile  : $pot"
    echo

    hashcat -m 22000 "$hc22000" "$WORDLIST" \
        --hwmon-disable \
        --quiet \
        --potfile-path "$pot" \
        --status \
        --status-timer=10 \
        2>/dev/null

    echo
    if hashcat -m 22000 "$hc22000" --show --potfile-path "$pot" --quiet 2>/dev/null | grep -q ":"; then
        hashcat -m 22000 "$hc22000" --show --potfile-path "$pot" --quiet 2>/dev/null > "$output"

        echo -e "${BGREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BGREEN}║       🔓  HANDSHAKE CRACKED!             ║${NC}"
        echo -e "${BGREEN}╚══════════════════════════════════════════╝${NC}"
        echo

        declare -A seen
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local ssid password key
            ssid=$(echo "$line"     | awk -F: '{print $(NF-1)}')
            password=$(echo "$line" | awk -F: '{print $NF}')
            key="${ssid}:${password}"
            [[ -n "${seen[$key]}" ]] && continue
            seen[$key]=1
            echo -e "  ${WHITE}SSID    :${NC} ${BCYAN}$ssid${NC}"
            echo -e "  ${WHITE}Password:${NC} ${BGREEN}$password${NC}"
            echo -e "  ${GRAY}──────────────────────────────────────────${NC}"
        done < "$output"
        unset seen

        echo
        print_success "Results saved → $output"
    else
        echo -e "${BRED}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BRED}║    ✗  Password NOT found in wordlist     ║${NC}"
        echo -e "${BRED}╚══════════════════════════════════════════╝${NC}"
        echo
        print_info "Try these next steps:"
        echo -e "${GRAY}  • Use a larger wordlist${NC}"
        echo -e "${GRAY}  • Add rules:  hashcat -m 22000 $hc22000 $WORDLIST -r /usr/share/hashcat/rules/best64.rule${NC}"
        echo -e "${GRAY}  • Brute force: hashcat -m 22000 $hc22000 -a 3 ?d?d?d?d?d?d?d?d${NC}"
    fi
}

# ==========================================
# VIEW RESULTS
# ==========================================
view_results() {
    print_section "Saved Results"
    if compgen -G "$CRACK_DIR/wpa_*" > /dev/null 2>&1; then
        echo -e "${GRAY}  Directory: $CRACK_DIR${NC}"
        echo
        local files=("$CRACK_DIR"/wpa_*)
        local i=1
        for f in "${files[@]}"; do
            echo -e "  ${BCYAN}[$i]${NC} $(basename "$f")  ${GRAY}($(wc -l < "$f") result(s))${NC}"
            ((i++))
        done
        echo
        read -p "$(echo -e "  ${BPURPLE}Enter number to view (Enter to skip)${NC}: ")" num
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#files[@]} )); then
            echo
            cat "${files[$((num-1))]}"
        fi
    else
        print_warning "No results yet. Go crack something! 👾"
    fi
}

# ==========================================
# MAIN MENU
# ==========================================
main_menu() {
    while true; do
        show_banner
        echo -e "  ${BCYAN}╔════════════════════════════════════════════╗${NC}"
        echo -e "  ${BCYAN}║${NC}  ${WHITE}WI-FI HANDSHAKE CRACKER — Main Menu    ${NC}${BCYAN}║${NC}"
        echo -e "  ${BCYAN}╚════════════════════════════════════════════╝${NC}"
        echo
        echo -e "  ${BGREEN}[1]${NC} ${WHITE}Crack Wi-Fi Handshake${NC}  ${GRAY}(.cap / .pcap / .pcapng)${NC}"
        echo -e "  ${BGREEN}[2]${NC} ${WHITE}View Results${NC}"
        echo -e "  ${BRED}[0]${NC} ${WHITE}Exit${NC}"
        echo
        read -p "$(echo -e "  ${BPURPLE}Choice [0-2]${NC}: ")" opt

        case "$opt" in
            1)
                prompt_target_file || { pause; continue; }
                crack_handshake "$TARGET_FILE"
                ;;
            2)
                view_results
                ;;
            0)
                echo
                echo -e "${BGREEN}  ✓ Session complete! Stay legal. 👾${NC}"
                echo
                exit 0
                ;;
            *)
                print_error "Invalid option: '$opt' — choose 0, 1, or 2"
                ;;
        esac

        pause
    done
}

# ==========================================
# ENTRY POINT
# ==========================================
if [[ $EUID -ne 0 ]]; then
    print_warning "Running as non-root. Some features may need root for GPU access."
    sleep 1
fi

show_banner
setup_dirs
check_deps
main_menu
