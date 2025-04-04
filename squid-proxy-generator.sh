#!/bin/bash

# Configuration
PROXY_IP="103.174.51.75"  # Will auto-detect if empty
PROXY_PORT="7771"
PROXY_USER="ithub1"
PROXY_PASSWORD="it-hub"
SQUID_CONF="/etc/squid/squid.conf"
PASSWORD_FILE="/etc/squid/passwords"

# Function to completely remove Squid
remove_squid() {
    echo "[+] Completely removing Squid and all configurations..."
    sudo systemctl stop squid 2>/dev/null || true
    sudo apt remove --purge squid squid-common -y
    sudo rm -rf /etc/squid
    sudo rm -rf /var/spool/squid
    sudo rm -f /etc/apt/sources.list.d/squid*
    sudo apt autoremove -y
    echo "[√] Squid completely removed."
}

# Install fresh Squid
install_squid() {
    echo "[+] Installing fresh Squid..."
    sudo apt update
    sudo apt install squid apache2-utils -y
    sudo systemctl stop squid
}

# Configure fresh Squid
configure_squid() {
    echo "[+] Creating optimized configuration..."

    # Create minimal config directory
    sudo mkdir -p /etc/squid/conf.d/
    sudo chown -R proxy:proxy /etc/squid

    cat <<EOL | sudo tee "$SQUID_CONF" > /dev/null
http_port $MAIN_IP:$PROXY_PORT

# Minimal configuration for maximum speed
cache deny all
maximum_object_size 0 KB
minimum_object_size 0 KB

# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASSWORD_FILE
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Performance
max_filedescriptors 65535
workers 4

# Timeouts
connect_timeout 30 seconds
read_timeout 300 seconds

# Security
via off
forwarded_for delete
request_header_access Via deny all
request_header_access X-Forwarded-For deny all
request_header_access Referer deny all
EOL

    # Create password file
    echo "[+] Creating authentication user..."
    sudo htpasswd -b -c "$PASSWORD_FILE" "$PROXY_USER" "$PROXY_PASSWORD"
    sudo chown proxy:proxy "$PASSWORD_FILE"
    sudo chmod 640 "$PASSWORD_FILE"
}

# System optimizations
optimize_system() {
    echo "[+] Applying system optimizations..."
    cat <<EOL | sudo tee /etc/sysctl.d/99-squid-optimization.conf > /dev/null
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_low_latency=1
net.ipv4.ip_forward=1
EOL
    sudo sysctl -p /etc/sysctl.d/99-squid-optimization.conf
}

# Main execution
main() {
    # Get main IP if not set
    if [ -z "$PROXY_IP" ]; then
        MAIN_IP=$(hostname -I | awk '{print $1}')
    else
        MAIN_IP="$PROXY_IP"
    fi

    # 1. Complete removal
    remove_squid

    # 2. Fresh install
    install_squid

    # 3. Configure
    configure_squid

    # 4. System optimizations
    optimize_system

    # Initialize and start
    echo "[+] Initializing Squid..."
    sudo squid -z 2>/dev/null || true
    
    echo "[+] Starting Squid service..."
    sudo systemctl start squid
    sudo systemctl enable squid

    # Firewall
    sudo ufw allow "$PROXY_PORT/tcp" >/dev/null 2>&1 || true

    # Verification
    echo -e "\n[✅] FRESH SQUID INSTALLATION COMPLETE!"
    echo -e "========================================="
    echo -e "Proxy Details:"
    echo -e "Address: $MAIN_IP"
    echo -e "Port: $PROXY_PORT"
    echo -e "Username: $PROXY_USER"
    echo -e "Password: $PROXY_PASSWORD"
    echo -e "========================================="
    echo -e "Test with:"
    echo -e "curl -x http://$PROXY_USER:$PROXY_PASSWORD@$MAIN_IP:$PROXY_PORT http://ifconfig.me"
    echo -e "\nCheck status: sudo systemctl status squid"
}

# Execute main function
main