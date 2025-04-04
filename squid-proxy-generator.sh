#!/bin/bash

# Configuration
PROXY_IP="103.174.51.75"
PROXY_PORT="7771"
PROXY_USER="ithub1"
PROXY_PASSWORD="it-hub"
SQUID_CONF="/etc/squid/squid.conf"
PASSWORD_FILE="/etc/squid/passwords"

# Get main IP if not set
if [ -z "$PROXY_IP" ]; then
    MAIN_IP=$(hostname -I | awk '{print $1}')
else
    MAIN_IP="$PROXY_IP"
fi

# Function to handle errors
handle_error() {
    echo "[!] Error occurred: $1"
    echo "[+] Checking Squid logs for details..."
    sudo tail -n 20 /var/log/squid/cache.log
    exit 1
}

# Clean removal of existing Squid
echo "[+] Removing existing Squid installation..."
{
    sudo systemctl stop squid || true
    sudo apt remove --purge squid squid-common -y
    sudo rm -rf /etc/squid /var/spool/squid
    sudo apt autoremove -y
} || handle_error "Failed to remove old Squid installation"

# Install fresh Squid
echo "[+] Installing fresh Squid package..."
{
    sudo apt update
    sudo apt install squid apache2-utils -y
} || handle_error "Failed to install Squid"

# Create minimal configuration
echo "[+] Creating optimized configuration..."
{
    sudo mkdir -p /etc/squid/conf.d/
    sudo chown -R proxy:proxy /etc/squid

    cat <<EOL | sudo tee "$SQUID_CONF" > /dev/null
http_port $MAIN_IP:$PROXY_PORT

# Minimal configuration
cache deny all
maximum_object_size 0 KB

# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASSWORD_FILE
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Performance
max_filedescriptors 65535
workers 2

# Security
via off
forwarded_for delete
dns_v4_first on
EOL
} || handle_error "Failed to create configuration"

# Create password file
echo "[+] Setting up authentication..."
{
    sudo touch "$PASSWORD_FILE"
    sudo htpasswd -b "$PASSWORD_FILE" "$PROXY_USER" "$PROXY_PASSWORD"
    sudo chown proxy:proxy "$PASSWORD_FILE"
    sudo chmod 640 "$PASSWORD_FILE"
} || handle_error "Failed to setup authentication"

# Initialize Squid
echo "[+] Initializing Squid directories..."
{
    sudo squid -z 2>/dev/null || true
} || echo "[!] Non-critical initialization warning"

# Fix permissions
echo "[+] Verifying permissions..."
{
    sudo chown -R proxy:proxy /var/log/squid/
    sudo chown -R proxy:proxy /var/spool/squid/
} || handle_error "Permission fix failed"

# Start Squid with error checking
echo "[+] Starting Squid service..."
{
    sudo systemctl restart squid
    sleep 2
    if ! systemctl is-active --quiet squid; then
        echo "[!] Squid failed to start. Checking logs..."
        sudo journalctl -u squid.service -n 50 --no-pager
        handle_error "Squid service failed to start"
    fi
}

# Final checks
echo "[+] Verifying installation..."
{
    echo "Checking Squid process:"
    pgrep squid || handle_error "Squid not running"
    
    echo "Testing proxy connection:"
    curl -x http://$PROXY_USER:$PROXY_PASSWORD@$MAIN_IP:$PROXY_PORT -m 5 http://ifconfig.me || \
    echo "[!] Initial test failed (may need to wait a moment)"
} || true

echo -e "\n[✅] SQUID PROXY INSTALLED AND RUNNING!"
echo "======================================"
echo "Proxy Address: $MAIN_IP:$PROXY_PORT"
echo "Username: $PROXY_USER"
echo "Password: $PROXY_PASSWORD"
echo "======================================"
echo "To check status: sudo systemctl status squid"
echo "To view logs: sudo tail -f /var/log/squid/access.log"