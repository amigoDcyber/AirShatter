#!/bin/bash
# =============================================================================
# AirShatter — core/colors.sh
# Centralized color and print helper definitions
# Developer: amigoDcyber
# =============================================================================

# Basic colors
RED='\033[0;31m'
BRED='\033[1;31m'
GREEN='\033[0;32m'
BGREEN='\033[1;32m'
YELLOW='\033[0;33m'
BYELLOW='\033[1;33m'
BLUE='\033[0;34m'
BBLUE='\033[1;34m'
PURPLE='\033[0;35m'
BPURPLE='\033[1;35m'
CYAN='\033[0;36m'
BCYAN='\033[1;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# ─── Print helpers ────────────────────────────────────────────────────────────
print_status()   { echo -e "${BGREEN}[${WHITE}+${BGREEN}]${NC} ${WHITE}$*${NC}"; }
print_info()     { echo -e "${BCYAN}[${WHITE}*${BCYAN}]${NC} ${CYAN}$*${NC}"; }
print_error()    { echo -e "${BRED}[${WHITE}-${BRED}]${NC} ${RED}$*${NC}"; }
print_warning()  { echo -e "${BYELLOW}[${WHITE}!${BYELLOW}]${NC} ${YELLOW}$*${NC}"; }
print_success()  { echo -e "${BGREEN}[${WHITE}✓${BGREEN}]${NC} ${BGREEN}$*${NC}"; }
print_question() { echo -e "${BPURPLE}[${WHITE}?${BPURPLE}]${NC} ${PURPLE}$*${NC}"; }

print_section() {
    echo
    echo -e "${BCYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}    $*${NC}"
    echo -e "${BCYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_banner_line() {
    echo -e "${BRED}$*${NC}"
}

pause() {
    echo
    read -rp "$(echo -e "${GRAY}  Press Enter to continue...${NC}")"
}

confirm() {
    # Usage: confirm "Are you sure?" && do_thing
    local msg="${1:-Continue?}"
    read -rp "$(echo -e "  ${BPURPLE}[?]${NC} ${PURPLE}${msg} [y/N]${NC}: ")" ans
    [[ "${ans,,}" == "y" ]]
}
