#!/bin/bash

# Configuration
MAIN_IP="103.174.51.75"
SUBNET_MASK="24"
PROXY_IPS=($(seq -f "103.174.51.%g" 76 85))  # IPs 103.174.51.76 to 103.174.51.85
NUM_PROXIES=10
PROXY_USER_PREFIX="proxyuser"
PROXY_PASSWORD="it-hub"
MAIN_USER="mainproxy"
MAIN_PASSWORD="it-hub"
SQUID_CONF="/etc/squid/squid.conf"
PASSWORD_FILE="/etc/squid/passwords"
OUTPUT_FILE="squid_proxies.txt"
DEFAULT_PORT=7771

# Clear previous setup
echo "[+] Cleaning previous configuration..."
sudo rm -f "$PASSWORD_FILE"
sudo touch "$PASSWORD_FILE"
sudo chown proxy:proxy "$PASSWORD_FILE"
sudo chmod 640 "$PASSWORD_FILE"

# Remove old IP aliases
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
for ip in "${PROXY_IPS[@]}"; do
    sudo ip addr del "$ip/$SUBNET_MASK" dev "$INTERFACE" 2>/dev/null || true
done

# Install Squid if needed
if ! command -v squid &> /dev/null; then
    echo "[+] Installing Squid..."
    sudo apt update
    sudo apt install squid apache2-utils -y
    sudo systemctl enable squid
fi

# Add IP aliases
echo "[+] Adding IP addresses..."
for ip in "${PROXY_IPS[@]}"; do
    sudo ip addr add "$ip/$SUBNET_MASK" dev "$INTERFACE" || true
done

# Configure Squid
echo "[+] Configuring Squid..."
sudo cp "$SQUID_CONF" "$SQUID_CONF.bak"

{
    echo "http_port $MAIN_IP:$DEFAULT_PORT"
    for ip in "${PROXY_IPS[@]}"; do
        echo "http_port $ip:$DEFAULT_PORT"
    done

    cat <<EOL
auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASSWORD_FILE
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
maximum_object_size 256 MB
cache_dir ufs /var/spool/squid 5000 16 256
request_header_access Via deny all
request_header_access X-Forwarded-For deny all
request_header_access Referer deny all
EOL
} | sudo tee "$SQUID_CONF" > /dev/null

# Generate users
echo "[+] Creating authentication users..."

# Main proxy user
echo "$MAIN_USER:$(openssl passwd -apr1 "$MAIN_PASSWORD")" | sudo tee "$PASSWORD_FILE" > /dev/null

# Additional proxy users
for ((i=1; i<=NUM_PROXIES; i++)); do
    USERNAME="${PROXY_USER_PREFIX}${i}"
    echo "$USERNAME:$(openssl passwd -apr1 "$PROXY_PASSWORD")" | sudo tee -a "$PASSWORD_FILE" > /dev/null
done

# Generate proxy list
echo "[+] Generating proxy list..."
echo "# SQUID PROXY LIST - Generated $(date)" > "$OUTPUT_FILE"
echo "http://$MAIN_USER:$MAIN_PASSWORD@$MAIN_IP:$DEFAULT_PORT" >> "$OUTPUT_FILE"

IP_INDEX=0
for ((i=1; i<=NUM_PROXIES; i++)); do
    USERNAME="${PROXY_USER_PREFIX}${i}"
    PROXY_IP="${PROXY_IPS[$IP_INDEX]}"
    echo "http://$USERNAME:$PROXY_PASSWORD@$PROXY_IP:$DEFAULT_PORT" >> "$OUTPUT_FILE"
    IP_INDEX=$((IP_INDEX + 1))
done

# Restart services
echo "[+] Restarting services..."
sudo squid -k reconfigure
sudo systemctl restart squid
sudo ufw allow "$DEFAULT_PORT/tcp" >/dev/null

# Completion
echo -e "\n[✅] SETUP COMPLETE!"
echo -e "================================="
echo -e "Main Proxy:"
echo -e "http://$MAIN_USER:$MAIN_PASSWORD@$MAIN_IP:$DEFAULT_PORT"
echo -e "\nGenerated $NUM_PROXIES proxies:"
echo -e "http://${PROXY_USER_PREFIX}1:$PROXY_PASSWORD@${PROXY_IPS[0]}:$DEFAULT_PORT"
echo -e "..."
echo -e "http://${PROXY_USER_PREFIX}${NUM_PROXIES}:$PROXY_PASSWORD@${PROXY_IPS[$((NUM_PROXIES-1))]}:$DEFAULT_PORT"
echo -e "================================="
echo -e "Full list saved to: $OUTPUT_FILE"
echo -e "Test with: curl -x http://$MAIN_USER:$MAIN_PASSWORD@$MAIN_IP:$DEFAULT_PORT http://example.com -I"