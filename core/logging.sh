#!/bin/bash
# =============================================================================
# AirShatter — core/logging.sh
# Structured session logging with module context and timestamps
# Developer: amigoDcyber
# =============================================================================

# LOG_DIR exported by airshatter.sh; fallback for standalone sourcing
LOG_DIR="${LOG_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../logs}"
LOG_FILE="${LOG_DIR}/airshatter_$(date +%Y%m%d).log"

# ─── Initialize log directory and write session header ────────────────────────
init_logging() {
    mkdir -p "$LOG_DIR" || {
        echo "WARNING: Cannot create log directory: $LOG_DIR"
        return 1
    }
    # Write session header once per day-file
    if [[ ! -f "$LOG_FILE" ]]; then
        {
            echo "============================================================"
            echo "  AirShatter Session Log"
            echo "  Date    : $(date '+%Y-%m-%d')"
            echo "  Host    : $(hostname)"
            echo "  User    : $(whoami)"
            echo "  Kernel  : $(uname -r)"
            echo "============================================================"
        } >> "$LOG_FILE"
    fi
}

# ─── Internal writer ──────────────────────────────────────────────────────────
# Format: [YYYY-MM-DD HH:MM:SS] [LEVEL  ] [MODULE        ] message
_log() {
    local level="$1"
    local module="$2"
    shift 2
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] [%-7s] [%-16s] %s\n' \
           "$ts" "$level" "$module" "$msg" >> "$LOG_FILE" 2>/dev/null
}

# ─── Public logging functions — module auto-detected from call stack ──────────
# Each logs its module name from the calling function's context when possible.
# Pass module explicitly via LOG_MODULE env var if needed.

_get_module() {
    # Use LOG_MODULE if set; otherwise derive from the caller's source file
    if [[ -n "$LOG_MODULE" ]]; then
        echo "$LOG_MODULE"
    else
        # Walk up the call stack to find a non-logging frame
        local i
        for (( i = 2; i < ${#FUNCNAME[@]}; i++ )); do
            local src="${BASH_SOURCE[$i]##*/}"
            [[ "$src" == "logging.sh" || "$src" == "colors.sh" ]] && continue
            echo "${src%.sh}"
            return
        done
        echo "airshatter"
    fi
}

log_info()    { _log "INFO"    "$(_get_module)" "$*"; }
log_success() { _log "SUCCESS" "$(_get_module)" "$*"; }
log_warning() { _log "WARNING" "$(_get_module)" "$*"; }
log_error()   { _log "ERROR"   "$(_get_module)" "$*"; }

log_action() {
    # log_action ACTION_TAG "detail message"
    # Logs a notable user-triggered event with clear ACTION prefix.
    local action="$1"; shift
    _log "ACTION" "$(_get_module)" "[$action] $*"
}

log_separator() {
    printf -- '%.0s─' {1..60} >> "$LOG_FILE" 2>/dev/null
    echo >> "$LOG_FILE" 2>/dev/null
}

# ─── Structured event loggers (called by specific modules) ────────────────────

# Called by scanner.sh
log_scan_result() {
    # log_scan_result SSID BSSID CHANNEL ENCRYPTION SIGNAL
    local LOG_MODULE="scanner"
    log_info "AP SSID='${1}' BSSID=${2} CH=${3} ENC=${4} SIG=${5}"
}

# Called by capture_manager.sh
log_capture_start() {
    # log_capture_start INTERFACE BSSID CHANNEL OUTPUT_PATH
    local LOG_MODULE="capture"
    log_action "CAPTURE_START" "iface=${1} bssid=${2:-all} ch=${3:-all} out=${4}"
}

log_capture_end() {
    # log_capture_end FILEPATH SIZE PACKETS
    local LOG_MODULE="capture"
    log_success "CAPTURE_DONE file=${1} size=${2} packets=${3:-unknown}"
}

# Called by analyzer.sh
log_analysis_start() {
    local LOG_MODULE="analyzer"
    log_action "ANALYZE_START" "file=${1} type=${2}"
}

log_analysis_result() {
    local LOG_MODULE="analyzer"
    log_info "ANALYZE_RESULT file=${1} handshakes=${2:-unknown} result=${3}"
}

# Called by crack_module.sh
log_crack_start() {
    local LOG_MODULE="crack"
    log_action "CRACK_START" "file=${1} wordlist=${2}"
}

log_crack_result() {
    local LOG_MODULE="crack"
    # result = FOUND | NOT_FOUND | ERROR
    log_action "CRACK_RESULT" "file=${1} result=${2}"
}

# Called by client_test.sh
log_client_test() {
    # log_client_test BSSID CLIENT_MAC COUNT
    local LOG_MODULE="client_test"
    log_action "CLIENT_TEST" "bssid=${1} client=${2:-broadcast} count=${3}"
}

# ─── View logs (main menu option 7) ───────────────────────────────────────────
view_logs() {
    print_section "Session Logs"

    if [[ ! -d "$LOG_DIR" ]] || [[ -z "$(ls -A "$LOG_DIR" 2>/dev/null)" ]]; then
        print_warning "No log files found in $LOG_DIR"
        return 0
    fi

    echo -e "  ${GRAY}Directory: $LOG_DIR${NC}"
    echo

    # Collect .log files
    local files=()
    for f in "$LOG_DIR"/*.log; do
        [[ -f "$f" ]] && files+=("$f")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        print_warning "No .log files found."
        return 0
    fi

    # List them
    printf "  ${BCYAN}%-5s %-35s %-8s %-12s${NC}\n" "No." "Filename" "Size" "Date"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..65})${NC}"

    local i=1
    for f in "${files[@]}"; do
        local size date
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        date=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1)
        printf "  ${WHITE}[%-3s]${NC} ${BGREEN}%-35s${NC} ${GRAY}%-8s %-12s${NC}\n" \
               "$i" "$(basename "$f")" "$size" "$date"
        ((i++))
    done

    echo
    echo -e "  ${WHITE}[f]${NC} ${GRAY}Filter view (grep a keyword)${NC}"
    echo -e "  ${WHITE}[0]${NC} ${GRAY}Back to main menu${NC}"
    echo
    read -rp "$(echo -e "  ${BPURPLE}Enter number to view${NC}: ")" num

    case "$num" in
        0|"") return 0 ;;
        f|F)
            read -rp "$(echo -e "  ${BPURPLE}Keyword to filter${NC}: ")" kw
            echo
            echo -e "${BCYAN}  ── Filtered log (keyword: $kw) ──────────────────────────${NC}"
            # Search all log files
            grep -h --color=never "$kw" "${files[@]}" 2>/dev/null | \
                sed 's/^\(.*\)\(\[ACTION\]\)/\1'"$(echo -e '\033[1;32m')"'\2'"$(echo -e '\033[0m')"'/' | \
                sed 's/^\(.*\)\(\[ERROR\]\)/\1'"$(echo -e '\033[1;31m')"'\2'"$(echo -e '\033[0m')"'/'
            echo -e "${BCYAN}  ─────────────────────────────────────────────────────────${NC}"
            ;;
        *)
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num < i )); then
                local target="${files[$((num-1))]}"
                echo
                echo -e "${BCYAN}  ── $(basename "$target") ──────────────────────────────────${NC}"

                # Color-code log levels in output
                cat "$target" | \
                    GREP_COLORS='ms=01;32' grep --color=always -E '\[SUCCESS\]|$' | \
                    GREP_COLORS='ms=01;31' grep --color=always -E '\[ERROR\]|$'   | \
                    GREP_COLORS='ms=01;33' grep --color=always -E '\[WARNING\]|$' | \
                    GREP_COLORS='ms=01;36' grep --color=always -E '\[ACTION\]|$'

                echo -e "${BCYAN}  ─────────────────────────────────────────────────────────${NC}"
                echo
                echo -e "  ${GRAY}Lines: $(wc -l < "$target")   Size: $(du -sh "$target" | cut -f1)${NC}"
            else
                print_error "Invalid selection."
            fi
            ;;
    esac
}
