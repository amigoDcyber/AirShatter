#!/bin/bash
# =============================================================================
# AirShatter — core/dependency_check.sh
# Dependency verification with distro-aware install guidance
# Developer: amigoDcyber
# =============================================================================

# ─── Detect Linux distribution ────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID,,}"
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# ─── Install hint per tool per distro ─────────────────────────────────────────
install_hint() {
    local tool="$1"
    local distro
    distro=$(detect_distro)

    declare -A arch_pkg=(
        [aircrack-ng]="aircrack-ng"
        [airodump-ng]="aircrack-ng"
        [aireplay-ng]="aircrack-ng"
        [hashcat]="hashcat"
        [hcxpcapngtool]="hcxtools"
        [hcxdumptool]="hcxdumptool"
        [iw]="iw"
        [ip]="iproute2"
        [xterm]="xterm"
        [tcpdump]="tcpdump"
        [wireshark]="wireshark-qt"
        [tshark]="wireshark-cli"
        [pdf2john]="john"
    )

    declare -A deb_pkg=(
        [aircrack-ng]="aircrack-ng"
        [airodump-ng]="aircrack-ng"
        [aireplay-ng]="aircrack-ng"
        [hashcat]="hashcat"
        [hcxpcapngtool]="hcxtools"
        [hcxdumptool]="hcxdumptool"
        [iw]="iw"
        [ip]="iproute2"
        [xterm]="xterm"
        [tcpdump]="tcpdump"
        [wireshark]="wireshark"
        [tshark]="tshark"
        [pdf2john]="john"
    )

    case "$distro" in
        arch|manjaro|endeavouros)
            local pkg="${arch_pkg[$tool]:-$tool}"
            echo "sudo pacman -S $pkg"
            ;;
        kali|debian|ubuntu|linuxmint|pop)
            local pkg="${deb_pkg[$tool]:-$tool}"
            echo "sudo apt install $pkg"
            ;;
        fedora|rhel|centos)
            echo "sudo dnf install $tool"
            ;;
        *)
            echo "Install '$tool' via your package manager"
            ;;
    esac
}

# ─── Check single tool ────────────────────────────────────────────────────────
check_tool() {
    local tool="$1"
    local required="${2:-false}"   # true = exit if missing

    if command -v "$tool" &>/dev/null; then
        local path
        path=$(command -v "$tool")
        print_success "$tool  ${GRAY}→ $path${NC}"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            print_error "$tool  ${GRAY}→ NOT FOUND (required)${NC}"
        else
            print_warning "$tool  ${GRAY}→ NOT FOUND (optional)${NC}"
        fi
        local hint
        hint=$(install_hint "$tool")
        echo -e "         ${GRAY}Install: ${WHITE}$hint${NC}"
        return 1
    fi
}

# ─── Full dependency scan ─────────────────────────────────────────────────────
check_all_dependencies() {
    print_section "Dependency Check"

    local distro
    distro=$(detect_distro)
    print_info "Detected distro: ${WHITE}$distro${NC}"
    echo

    local missing_required=()
    local missing_optional=()

    echo -e "  ${WHITE}── Required Tools ──────────────────────────────${NC}"
    local required_tools=("aircrack-ng" "airodump-ng" "iw" "ip")
    for t in "${required_tools[@]}"; do
        check_tool "$t" "true" || missing_required+=("$t")
    done

    echo
    echo -e "  ${WHITE}── Cracking Tools ──────────────────────────────${NC}"
    local crack_tools=("hashcat" "hcxpcapngtool")
    for t in "${crack_tools[@]}"; do
        check_tool "$t" "true" || missing_required+=("$t")
    done

    echo
    echo -e "  ${WHITE}── Optional Tools ──────────────────────────────${NC}"
    local optional_tools=("xterm" "wireshark" "tshark" "tcpdump" "aireplay-ng")
    for t in "${optional_tools[@]}"; do
        check_tool "$t" "false" || missing_optional+=("$t")
    done

    echo
    log_separator
    log_info "Dependency check — distro: $distro"

    if [[ ${#missing_required[@]} -gt 0 ]]; then
        echo
        print_error "Missing required tools: ${missing_required[*]}"
        print_info "Install them and re-run AirShatter."
        log_error "Missing required: ${missing_required[*]}"
        echo
        read -rp "$(echo -e "  ${BPURPLE}Continue anyway? [y/N]${NC}: ")" ans
        [[ "${ans,,}" != "y" ]] && exit 1
    else
        print_success "All required tools are installed."
        log_success "All required dependencies satisfied"
    fi

    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        print_warning "Optional tools missing: ${missing_optional[*]}"
        log_warning "Missing optional: ${missing_optional[*]}"
    fi

    sleep 1
}

# ─── Quick check (used by modules before running) ─────────────────────────────
require_tool() {
    local tool="$1"
    if ! command -v "$tool" &>/dev/null; then
        print_error "Required tool not found: $tool"
        local hint
        hint=$(install_hint "$tool")
        print_info "Install with: $hint"
        return 1
    fi
    return 0
}
