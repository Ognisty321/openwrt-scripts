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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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
        command_exists $cmd || { log "Required command '$cmd' not found" >&2; exit 1; }
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

    # Stop the Tailscale service
    log "Stopping Tailscale service..."
    /etc/init.d/tailscale stop

    # Run Tailscale cleanup
    if command_exists tailscaled; then
        log "Running Tailscale cleanup..."
        tailscaled --cleanup
    else
        log "Tailscaled not found, skipping cleanup..."
    fi

    # Remove the Tailscale package
    log "Removing Tailscale package..."
    opkg remove tailscale

    # Remove Tailscale configurations
    log "Removing Tailscale configurations..."
    uci -q delete network.${INTERFACE_NAME}
    uci -q delete firewall.${ZONE_NAME}
    uci -q del_list firewall.${ZONE_NAME}.dest_zone='lan'
    uci -q del_list firewall.${ZONE_NAME}.dest_zone='wan'
    uci -q del_list firewall.${ZONE_NAME}.src_zone='lan'
    uci commit

    # Remove Tailscale init script modifications
    log "Removing Tailscale init script modifications..."
    sed -i "/procd_append_param command --tun ${INTERFACE_NAME}/d" /etc/init.d/tailscale

    # Remove Tailscale state directory
    log "Removing Tailscale state directory..."
    rm -rf /var/lib/tailscale

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

# Function to prompt user for input
prompt_user() {
    local prompt="$1"
    local variable="$2"
    local default="$3"

    if [ -n "$default" ]; then
        prompt="$prompt (default: $default)"
    fi

    printf "%s: " "$prompt"
    read -r user_input

    if [ -z "$user_input" ] && [ -n "$default" ]; then
        user_input="$default"
    fi

    eval "$variable=\"$user_input\""
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
}

# Function to configure Tailscale
configure_tailscale() {
    log "Configuring Tailscale..."

    prompt_user "Enter your Tailscale auth key" AUTH_KEY
    prompt_user "Enter the routes to advertise (comma-separated, e.g., 10.0.0.0/24,192.168.1.0/24)" ROUTES
    prompt_user "Do you want to set up this device as a subnet router? (yes/no)" SETUP_SUBNET_ROUTER "no"
    prompt_user "Do you want to set up this device as an exit node? (yes/no)" SETUP_EXIT_NODE "no"

    local cmd="tailscale up --authkey=${AUTH_KEY} --netfilter-mode=off"

    if [ -n "$ROUTES" ]; then
        cmd="${cmd} --advertise-routes=${ROUTES}"

        if [ "$SETUP_SUBNET_ROUTER" = "yes" ]; then
            cmd="${cmd} --accept-routes"
        fi
    fi

    if [ "$SETUP_EXIT_NODE" = "yes" ]; then
        cmd="${cmd} --advertise-exit-node"
    fi

    eval $cmd

    log "Tailscale configuration completed."
}

# Function to set up exit node routing
setup_exit_node_routing() {
    if [ "$SETUP_EXIT_NODE" = "yes" ]; then
        log "Setting up exit node routing..."

        # Disable default packet forwarding
        uci_set "firewall.@defaults[0].forward='REJECT'"

        # Disable LAN to WAN forwarding
        uci del_list firewall.@zone[0].dest_zone='wan'

        uci commit

        prompt_user "Enter the hostname of the exit node you want to use (leave blank to skip)" EXIT_NODE

        local cmd="tailscale up"

        if [ -n "$EXIT_NODE" ]; then
            cmd="${cmd} --exit-node=${EXIT_NODE} --exit-node-allow-lan-access=true"
        fi

        eval $cmd

        log "Exit node routing configured."
    else
        log "Not setting up as an exit node."
    fi
}

# Function to optimize network settings for Tailscale performance
optimize_network_settings() {
    if [ -d "/etc/networkd-dispatcher" ]; then
        log "Optimizing network settings for Tailscale performance..."

        mkdir -p /etc/networkd-dispatcher/routable.d/pre-up.d
        cat > /etc/networkd-dispatcher/routable.d/pre-up.d/ethtool-config-udp-gro << EOF
#!/bin/sh

ethtool --offload \$IFACE rx-checksum off
ethtool --offload \$IFACE tx-checksum-ip-generic off
ethtool --change \$IFACE tso off gro off
EOF
        chmod +x /etc/networkd-dispatcher/routable.d/pre-up.d/ethtool-config-udp-gro
        systemctl restart networkd-dispatcher

        log "Network settings optimized."
    else
        log "Network dispatcher not found. Skipping network settings optimization."
    fi
}

# Main script execution starts here
log "Starting Tailscale installation and configuration script..."

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
    configure_tailscale
    setup_exit_node_routing
    optimize_network_settings
fi

log "Script execution completed."
