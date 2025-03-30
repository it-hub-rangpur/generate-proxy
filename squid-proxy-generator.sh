#!/bin/bash

# Configuration
MAIN_IP="103.174.51.75"
PROXY_PORT="7771"
PROXY_USER="ithub1"
PROXY_PASSWORD="it-hub"
SQUID_CONF="/etc/squid/squid.conf"
PASSWORD_FILE="/etc/squid/passwords"

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

# Create new config
echo "[+] Creating new configuration..."
cat <<EOL | sudo tee "$SQUID_CONF" > /dev/null
http_port $MAIN_IP:$PROXY_PORT

# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASSWORD_FILE
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Security headers
request_header_access Via deny all
request_header_access X-Forwarded-For deny all
request_header_access Referer deny all

# Cache settings (optional)
cache_dir ufs /var/spool/squid 100 16 256
maximum_object_size 256 MB
EOL

# Create password file
echo "[+] Creating authentication user..."
sudo htpasswd -b -c "$PASSWORD_FILE" "$PROXY_USER" "$PROXY_PASSWORD"
sudo chown proxy:proxy "$PASSWORD_FILE"
sudo chmod 640 "$PASSWORD_FILE"

# Initialize cache
echo "[+] Initializing cache..."
sudo squid -z

# Restart Squid
echo "[+] Restarting services..."
sudo systemctl restart squid

# Allow firewall port
sudo ufw allow "$PROXY_PORT/tcp" >/dev/null 2>&1 || true

# Completion
echo -e "\n[✅] SQUID PROXY SETUP COMPLETE!"
echo -e "================================="
echo -e "Proxy Details:"
echo -e "Address: $MAIN_IP"
echo -e "Port: $PROXY_PORT"
echo -e "Username: $PROXY_USER"
echo -e "Password: $PROXY_PASSWORD"
echo -e "================================="
echo -e "Test with:"
echo -e "curl -x http://$PROXY_USER:$PROXY_PASSWORD@$MAIN_IP:$PROXY_PORT http://ifconfig.me"