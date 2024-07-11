#!/bin/sh

set -e

# Global variables
INTERFACE_NAME="tailscale0"
ZONE_NAME="tailscale"
SMALL_BINARY=0
UNINSTALL=0
UPDATE=0
VERBOSE=0
LOG_FILE="/tmp/tailscale_install.log"

# Function to log messages
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

log_verbose() {
    [ "$VERBOSE" -eq 1 ] && log "$1"
}

# Function to set UCI options with error handling
uci_set() {
    uci set "$1" || { log "Failed to set UCI option: $1" >&2; exit 1; }
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --interface NAME   Set interface name (default: tailscale0)"
    echo "  --zone NAME        Set zone name (default: tailscale)"
    echo "  --small            Use smaller Tailscale binary"
    echo "  --uninstall        Uninstall Tailscale"
    echo "  --update           Update Tailscale"
    echo "  --verbose          Enable verbose logging"
    echo "  --help             Show this help message"
}

# Function to check if Tailscale is installed
is_tailscale_installed() {
    if opkg list-installed | grep -q "^tailscale "; then
        return 0
    else
        return 1
    fi
}

# Function to check OpenWrt version
check_openwrt_version() {
    local version=$(cat /etc/openwrt_version)
    if [ -z "$version" ]; then
        log "Unable to determine OpenWrt version" >&2
        exit 1
    fi
    log "OpenWrt version: $version"
}

# Function to backup configurations
backup_config() {
    cp /etc/config/network /etc/config/network.bak
    cp /etc/config/firewall /etc/config/firewall.bak
    log "Configuration files backed up"
}

# Function to check dependencies
check_dependencies() {
    for cmd in opkg uci sed grep; do
        which $cmd >/dev/null 2>&1 || { log "Required command '$cmd' not found" >&2; exit 1; }
    done
    log "All required dependencies are available"
}

# Function to uninstall Tailscale
uninstall_tailscale() {
    log "Uninstalling Tailscale..."

    if ! is_tailscale_installed; then
        log "Tailscale is not installed. Nothing to uninstall."
        return
    fi

    /etc/init.d/tailscale stop
    opkg remove tailscale
    uci delete network.${INTERFACE_NAME}
    uci delete firewall.${ZONE_NAME}
    uci -q del_list firewall.${ZONE_NAME}.dest_zone='lan'
    uci -q del_list firewall.${ZONE_NAME}.dest_zone='wan'
    uci -q del_list firewall.${ZONE_NAME}.src_zone='lan'
    uci commit
    sed -i "/procd_append_param command --tun ${INTERFACE_NAME}/d" /etc/init.d/tailscale

    log "Tailscale has been uninstalled and configurations removed."
}

# Function to update Tailscale
update_tailscale() {
    log "Updating Tailscale..."

    if ! is_tailscale_installed; then
        log "Tailscale is not installed. Please install it first."
        return
    fi

    opkg update || { log "Failed to update package lists" >&2; exit 1; }
    opkg upgrade tailscale || { log "Failed to upgrade Tailscale" >&2; exit 1; }

    log "Restarting Tailscale service..."
    /etc/init.d/tailscale restart

    log "Tailscale has been updated."
}

# Function to install Tailscale
install_tailscale() {
    log "Updating package lists..."
    opkg update || { log "Failed to update package lists" >&2; exit 1; }

    if is_tailscale_installed; then
        log "Tailscale is already installed. Use --update to upgrade."
        return
    fi

    log "Installing Tailscale..."
    if [ "$SMALL_BINARY" -eq 1 ]; then
        log "Installing smaller Tailscale binary..."
        # Add commands to download and install smaller binary
        # This part needs to be implemented based on the actual source and method for the smaller binary
        log "Small binary installation not implemented yet."
    else
        opkg install tailscale || { log "Failed to install Tailscale" >&2; exit 1; }
    fi

    log "Configuring network interface..."
    uci_set "network.${INTERFACE_NAME}=interface"
    uci_set "network.${INTERFACE_NAME}.proto='unmanaged'"
    uci_set "network.${INTERFACE_NAME}.device=${INTERFACE_NAME}"

    log "Configuring firewall..."
    uci_set "firewall.${ZONE_NAME}=zone"
    uci_set "firewall.${ZONE_NAME}.name=${ZONE_NAME}"
    uci_set "firewall.${ZONE_NAME}.input='ACCEPT'"
    uci_set "firewall.${ZONE_NAME}.output='ACCEPT'"
    uci_set "firewall.${ZONE_NAME}.forward='ACCEPT'"
    uci_set "firewall.${ZONE_NAME}.masq='1'"
    uci_set "firewall.${ZONE_NAME}.mtu_fix='1'"
    uci add_list firewall.${ZONE_NAME}.network=${INTERFACE_NAME}
    uci add_list firewall.${ZONE_NAME}.dest_zone='lan'
    uci add_list firewall.${ZONE_NAME}.dest_zone='wan'
    uci add_list firewall.${ZONE_NAME}.src_zone='lan'

    uci commit

    log "Modifying Tailscale init script..."
    sed -i "/procd_append_param command/ a\    procd_append_param command --tun ${INTERFACE_NAME}" /etc/init.d/tailscale

    log "Installing iptables-nft..."
    opkg install iptables-nft || { log "Failed to install iptables-nft" >&2; exit 1; }

    log "Restarting Tailscale service..."
    /etc/init.d/tailscale restart

    log "Starting Tailscale..."
    tailscale up --netfilter-mode=off

    log "Tailscale has been installed and configured. Please complete the setup by running 'tailscale up' and following the authentication link."
}

# Main script execution starts here
log "Starting Tailscale installation script..."

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    log "This script must be run as root" >&2
    exit 1
fi

# Parse command-line arguments
while [ "$1" != "" ]; do
    case $1 in
        --interface ) shift
                      INTERFACE_NAME=$1
                      ;;
        --zone )      shift
                      ZONE_NAME=$1
                      ;;
        --small )     SMALL_BINARY=1
                      ;;
        --uninstall ) UNINSTALL=1
                      ;;
        --update )    UPDATE=1
                      ;;
        --verbose )   VERBOSE=1
                      ;;
        --help )      show_help
                      exit 0
                      ;;
        * )           log "Unknown parameter: $1"
                      show_help
                      exit 1
    esac
    shift
done

# Run pre-installation checks
check_dependencies
check_openwrt_version
backup_config

# Perform requested action
if [ "$UNINSTALL" -eq 1 ]; then
    uninstall_tailscale
elif [ "$UPDATE" -eq 1 ]; then
    update_tailscale
else
    install_tailscale
fi

log "Script execution completed."
