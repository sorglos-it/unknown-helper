#!/bin/bash

# ULH Bootstrap Library - Common initialization and utilities for all scripts
# Source this file at the start of each script in assets/scripts/:
#   source "$(dirname "$0")/../../classes/bootstrap.sh"

# Load colors from centralized library
source "${BASH_SOURCE%/*}/colors.sh"

# ============================================================
# PARAMETER PARSING
# ============================================================

# Parse parameters from ACTION,VAR1=val1,VAR2=val2 format
# Extracts ACTION and sets environment variables from key=value pairs
# Usage in script: parse_parameters "$1"
parse_parameters() {
    local full_params="$1"
    
    # Extract action (first part before comma)
    ACTION="${full_params%%,*}"
    
    # Extract remaining parameters
    local params_rest="${full_params#*,}"
    
    # Parse key=value pairs and export as environment variables
    if [[ -n "$params_rest" && "$params_rest" != "$full_params" ]]; then
        while IFS='=' read -r key val; do
            [[ -n "$key" ]] && export "$key=$val"
        done <<< "${params_rest//,/$'\n'}"
    fi
}

# ============================================================
# LOGGING
# ============================================================

log_info() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}✗${NC} %s\n" "$1"
    exit 1
}

log_section() {
    printf "\n${BLUE}▶${NC} %s\n" "$1"
}

# Same names as on the menu side (core.sh) - many scripts use these.
# Unlike log_error, msg_err does not exit.
msg_ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
msg_info() { printf "${CYAN}ℹ${NC} %s\n" "$*"; }
msg_warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
msg_err()  { printf "${RED}✗${NC} %s\n" "$*" >&2; }

# Root rights for the package manager: nothing as root, else sudo.
if (( EUID == 0 )); then SUDO=""
elif command -v sudo &>/dev/null; then SUDO="sudo"
else SUDO="no_root"
fi
no_root() { log_error "Needs root rights: install sudo, or start ulh as root."; }

# ============================================================
# OS DETECTION & PACKAGE MANAGER
# ============================================================

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_DISTRO="${ID,,}"
    else
        log_error "Cannot detect OS"
    fi
    
    case "$OS_DISTRO" in
        ubuntu|debian|raspbian|linuxmint|pop)
            PKG_TYPE="deb"
            PKG_UPDATE="$SUDO apt-get update"
            PKG_INSTALL="$SUDO apt-get install -y"
            PKG_UNINSTALL="$SUDO apt-get remove -y"
            ;;
        fedora|rhel|centos|rocky|alma)
            PKG_TYPE="rpm"
            PKG_UPDATE="$SUDO dnf check-update || true"
            PKG_INSTALL="$SUDO dnf install -y"
            PKG_UNINSTALL="$SUDO dnf remove -y"
            ;;
        arch|archarm|manjaro|endeavouros)
            PKG_TYPE="pacman"
            PKG_UPDATE="$SUDO pacman -Sy"
            PKG_INSTALL="$SUDO pacman -S --noconfirm"
            PKG_UNINSTALL="$SUDO pacman -R --noconfirm"
            ;;
        opensuse*|sles)
            PKG_TYPE="zypper"
            PKG_UPDATE="$SUDO zypper refresh"
            PKG_INSTALL="$SUDO zypper install -y"
            PKG_UNINSTALL="$SUDO zypper remove -y"
            ;;
        alpine)
            PKG_TYPE="apk"
            PKG_UPDATE="$SUDO apk update"
            PKG_INSTALL="$SUDO apk add"
            PKG_UNINSTALL="$SUDO apk del"
            ;;
        proxmox)
            PKG_TYPE="deb"
            PKG_UPDATE="$SUDO apt-get update"
            PKG_INSTALL="$SUDO apt-get install -y"
            PKG_UNINSTALL="$SUDO apt-get remove -y"
            ;;
        *)
            log_error "Unsupported distribution: $OS_DISTRO"
            ;;
    esac
}

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if OS is specific distro (case-insensitive)
is_os() {
    [[ "${OS_DISTRO}" == "$1" ]]
}

# Check if OS family matches
is_os_family() {
    case "$1" in
        debian)
            [[ "$PKG_TYPE" == "deb" ]]
            ;;
        redhat)
            [[ "$PKG_TYPE" == "rpm" ]]
            ;;
        arch)
            [[ "$PKG_TYPE" == "pacman" ]]
            ;;
        suse)
            [[ "$PKG_TYPE" == "zypper" ]]
            ;;
        alpine)
            [[ "$PKG_TYPE" == "apk" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================
# UTILITY: Print usage from the catalog (assets/catalog.yaml)
# ============================================================

# Print available actions with parameters from the catalog
# Format: script_name "action,VAR1=default1,VAR2=default2"
# NOTE: Does NOT call exit - caller must handle that
print_usage() {
    local script_name="${1:-${0##*/}}"
    script_name="${script_name%.sh}"
    
    printf "${RED}✗${NC} %s\n" "Unknown action: $ACTION"
    echo ""
    echo "Usage:"
    
    # The catalog sits next to this file: classes/../assets/catalog.yaml
    local config_file="${BASH_SOURCE%/*}/../assets/catalog.yaml"
    
    if [[ -f "$config_file" ]]; then
        # Find yq binary
        local yq_bin
        if [[ -x "${BASH_SOURCE%/*}/../vendor/yq/yq-amd64" ]]; then
            yq_bin="${BASH_SOURCE%/*}/../vendor/yq/yq-amd64"
        elif command -v yq &>/dev/null; then
            yq_bin="yq"
        else
            # Fallback to simple action listing
            sed -n "/^  $script_name:/,/^  [^ ]/p" "$config_file" | \
            grep "name:" | \
            sed 's/.*name: "/  '"$script_name"' "/' | \
            sed 's/"$/\"/'
            exit 1
        fi
        
        # Use yq to extract actions with parameters and format for display
        # Build a temporary awk script to format the output
        $yq_bin eval '.scripts.'"${script_name}"'.actions[] | .name + "|" + ((.prompts // []) | map(.variable + "=" + (.default // "")) | join(","))' "$config_file" | \
        while IFS='|' read -r action params; do
            if [[ -n "$params" ]]; then
                echo "  $script_name \"$action,$params\""
            else
                echo "  $script_name \"$action\""
            fi
        done
    else
        echo "    (catalog.yaml not found)"
    fi
    
    exit 1
}

# ============================================================
# CERTIFICATE NAME CHECK
# ============================================================

# cert_covers_name says whether the certificate in $1 answers for the name or
# address in $2. It reads the SENTENCE openssl prints, not its exit code.
#
# Why, measured on 4.11.2026 with one certificate for CN=a.example.org,
# SAN "DNS:a.example.org,IP:192.168.1.10", asked for b.example.org:
#
#   OpenSSL 3.0.2  (Ubuntu 22.04)  exit 0   "Hostname b.example.org does NOT match certificate"
#   OpenSSL 3.0.13 (Ubuntu 24.04)  exit 0   same sentence
#   OpenSSL 3.0.22 (Debian 12)     exit 0   same sentence
#   OpenSSL 3.5.7  (Debian 13)     exit 1   same sentence
#
# So below OpenSSL 3.5 the tool ends with 0 whether the name fits or not: it
# SAYS the verdict and does not signal it. Everything that read $? there took a
# certificate for a FOREIGN name as fitting, and every check next to it ("does
# it fit?") was true for every name. -checkip behaves the same way; -checkend
# and "openssl verify" do NOT - they set their code correctly on all four
# versions, so nothing else here needs this treatment.
#
# The sentence is the same text on all four versions, so this decides right on
# the old ones and on the new ones alike. Anything else than the two known
# sentences - an unreadable file, a changed wording, no openssl - counts as "it
# does not fit": a certificate is only left in place when the tool SAID so.
#
# Exactly ONE of the two is asked, chosen by the shape of the string, and that
# is not a nicety: "-checkip <a name that is no address>" answers "IP
# db-2.ngc.test does match certificate" - a match claimed out of nothing, for a
# certificate that carries no address at all. Measured on 4.11.2026 on OpenSSL
# 3.0.13 AND on 3.5.7, so this one is not a version difference but how the tool
# behaves. A first attempt at this helper asked both and took one "does match",
# and that version accepted every foreign name on both versions - the test
# cases below caught it.
#
# The old code had the same fallback: ngc-db.sh asked -checkhost and then
# -checkip, so even reading the output of THAT would have kept a foreign
# certificate. The hole in ngc-db was therefore two holes, not one.
cert_covers_name() {
    local opt out
    case "$2" in
        *:*)       opt=-checkip ;;    # an IPv6 address
        *[!0-9.]*) opt=-checkhost ;;  # anything with a letter is a name
        *.*.*.*)   opt=-checkip ;;    # four groups of digits: IPv4
        *)         opt=-checkhost ;;
    esac
    out="$(openssl x509 -in "$1" -noout "$opt" "$2" 2>/dev/null)"
    # "does NOT match" is asked FIRST, so no wording can be read as the other
    # one by accident, and anything else at all - an empty answer, an
    # unreadable file, no openssl on the machine - counts as "it does not fit".
    case "$out" in
        *"does NOT match certificate"*) return 1 ;;
        *"does match certificate"*)     return 0 ;;
        *)                              return 1 ;;
    esac
}

# ============================================================
# EXPORT BOOTSTRAP AS COMPLETE
# ============================================================

export BOOTSTRAP_LOADED=1
