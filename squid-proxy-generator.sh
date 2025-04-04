#!/bin/bash

# Configuration
PROXY_IP="103.174.51.75"  # Will auto-detect if empty
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

# Install Squid if needed
if ! command -v squid &> /dev/null; then
    echo "[+] Installing Squid..."
    sudo apt update
    sudo apt install squid apache2-utils -y
    sudo systemctl enable squid
fi

# Backup old config
echo "[+] Backing up old configuration..."
sudo cp "$SQUID_CONF" "$SQUID_CONF.bak"

# Create optimized configuration
echo "[+] Creating optimized configuration..."
cat <<EOL | sudo tee "$SQUID_CONF" > /dev/null
http_port $MAIN_IP:$PROXY_PORT

# COMPLETE DISABLE CACHING - PASSTHROUGH MODE
cache deny all
maximum_object_size 0 KB
minimum_object_size 0 KB

# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASSWORD_FILE
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Performance tuning
max_filedescriptors 65535
workers 4

# Timeouts (shorter for better performance)
forward_timeout 30 seconds
connect_timeout 15 seconds
read_timeout 300 seconds
client_lifetime 1 hour

# Security headers
via off
forwarded_for delete
request_header_access Via deny all
request_header_access X-Forwarded-For deny all
request_header_access Referer deny all

# Bypass proxy for local traffic
acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
http_access allow localnet
EOL

# Create password file
echo "[+] Creating authentication user..."
sudo htpasswd -b -c "$PASSWORD_FILE" "$PROXY_USER" "$PROXY_PASSWORD"
sudo chown proxy:proxy "$PASSWORD_FILE"
sudo chmod 640 "$PASSWORD_FILE"

# Apply system optimizations
echo "[+] Applying system optimizations..."
echo "net.core.rmem_max=1048576" | sudo tee -a /etc/sysctl.conf
echo "net.core.wmem_max=1048576" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_rmem=4096 1048576 1048576" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_wmem=4096 1048576 1048576" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Initialize Squid
echo "[+] Initializing Squid..."
sudo squid -z 2>/dev/null || true

# Restart Squid
echo "[+] Restarting services..."
sudo systemctl restart squid

# Allow firewall port
sudo ufw allow "$PROXY_PORT/tcp" >/dev/null 2>&1 || true

# Completion
echo -e "\n[✅] ULTRA-FAST SQUID PROXY SETUP COMPLETE!"
echo -e "========================================="
echo -e "Proxy Details:"
echo -e "Address: $MAIN_IP"
echo -e "Port: $PROXY_PORT"
echo -e "Username: $PROXY_USER"
echo -e "Password: $PROXY_PASSWORD"
echo -e "========================================="
echo -e "Test with:"
echo -e "curl -x http://$PROXY_USER:$PROXY_PASSWORD@$MAIN_IP:$PROXY_PORT http://ifconfig.me"
echo -e "\nNote: Running in full passthrough mode for maximum speed"