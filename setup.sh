#!/usr/bin/env bash
set -euo pipefail

echo "TechCorp Infrastructure Setup Script"
echo "===================================="

# Safety: ensure created files are not world-readable by default
umask 077

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

get_public_ip() {
    # Prefer dig (OpenDNS) for privacy; fall back to curl when necessary
    if cmd_exists dig; then
        dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || true
    elif cmd_exists curl; then
        curl -s https://ifconfig.me || true
    else
        echo ""
    fi
}

echo
# --- SSH key handling ---
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    read -r -p "SSH key not found. Generate new SSH key pair now? (y/N): " gen_key
    gen_key=${gen_key:-N}
    if [[ "$gen_key" =~ ^([yY])$ ]]; then
        read -r -p "Enter passphrase for the new key (leave empty for none): " -s passphrase
        echo
        if [ -z "$passphrase" ]; then
            ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N "" || true
        else
            ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N "$passphrase" || true
        fi
        echo "SSH key generated at $HOME/.ssh/id_rsa"
    else
        echo "Skipping SSH key generation. Ensure you have an SSH key at $HOME/.ssh/id_rsa"
    fi
else
    echo "SSH key already exists at $HOME/.ssh/id_rsa"
fi

# --- IP detection ---
echo
read -r -p "Auto-detect your public IP? (Y/n): " autodetect
autodetect=${autodetect:-Y}
if [[ "$autodetect" =~ ^([yY]|)$ ]]; then
    CURRENT_IP=$(get_public_ip)
    if [ -z "$CURRENT_IP" ]; then
        echo "Auto-detection failed. Please enter your public IP (e.g. 203.0.113.1):"
        read -r CURRENT_IP
    else
        echo "Detected public IP: $CURRENT_IP"
    fi
else
    read -r -p "Enter your public IP (e.g. 203.0.113.1): " CURRENT_IP
fi

# Append /32 if the user didn't provide a CIDR
if [[ "$CURRENT_IP" != */* ]]; then
    CIDR="${CURRENT_IP}/32"
else
    CIDR="$CURRENT_IP"
fi

# --- terraform.tfvars creation/backup ---
echo
if [ -f terraform.tfvars ]; then
    read -r -p "A terraform.tfvars already exists. Overwrite with detected IP ${CIDR}? (y/N): " overwrite
    overwrite=${overwrite:-N}
    if [[ ! "$overwrite" =~ ^([yY])$ ]]; then
        echo "Keeping existing terraform.tfvars. Edit it manually if necessary."
    else
        if [ -f terraform.tfvars ]; then
            cp terraform.tfvars terraform.tfvars.bak
            echo "Backup saved to terraform.tfvars.bak"
        fi
        if [ -f terraform.tfvars.example ]; then
            cp terraform.tfvars.example terraform.tfvars
            sed -i "s|YOUR_IP_ADDRESS|${CIDR}|g" terraform.tfvars
            chmod 600 terraform.tfvars || true
            echo "terraform.tfvars overwritten with IP: ${CIDR}"
        else
            echo "No terraform.tfvars.example found; please create terraform.tfvars manually."
        fi
    fi
else
    if [ -f terraform.tfvars.example ]; then
        cp terraform.tfvars.example terraform.tfvars
        sed -i "s|YOUR_IP_ADDRESS|${CIDR}|g" terraform.tfvars
        chmod 600 terraform.tfvars || true
        echo "terraform.tfvars created with IP: ${CIDR}"
    else
        echo "No terraform.tfvars.example found; please create terraform.tfvars manually."
    fi
fi

echo
echo "Setup complete. Next steps:"
echo "- Review terraform.tfvars and ensure it is not committed to source control (add to .gitignore)" 
echo "- Run: terraform init; terraform plan; terraform apply"
