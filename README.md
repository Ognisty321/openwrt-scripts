# OpenWrt Scripts Collection

This repository contains a collection of useful scripts for OpenWrt routers. These scripts are designed to simplify various tasks such as installing and managing packages, configuring network settings, and enhancing router functionality.

## Scripts

### 1. Tailscale Installation Script

`tailscale_install.sh` - This script automates the process of installing, updating, and uninstalling Tailscale on OpenWrt routers.

#### Features:
- Installs Tailscale and configures necessary network and firewall settings
- Updates existing Tailscale installation
- Uninstalls Tailscale and removes associated configurations
- Supports custom interface and zone naming
- Option for verbose logging

#### Usage:
```
./tailscale_install.sh [OPTIONS]

Options:
  --interface NAME   Set interface name (default: tailscale0)
  --zone NAME        Set zone name (default: tailscale)
  --small            Use smaller Tailscale binary (not implemented yet)
  --uninstall        Uninstall Tailscale
  --update           Update Tailscale
  --verbose          Enable verbose logging
  --help             Show this help message
```

#### Examples:
- Install Tailscale: `./tailscale_install.sh`
- Update Tailscale: `./tailscale_install.sh --update`
- Uninstall Tailscale: `./tailscale_install.sh --uninstall`
