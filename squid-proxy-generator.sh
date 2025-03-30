#!/bin/bash

# Configuration
MAIN_IP="103.174.51.75"
SUBNET_MASK="24"
PROXY_IPS=($(seq -f "103.174.51.%g" 76 85))  # Generate IPs from 103.174.51.76 to 103.174.51.85
NUM_PROXIES=10                              # Number of proxies to generate
PROXY_USER_PREFIX="ithub"                   # Username prefix
PROXY_PASSWORD="it-hub$password"            # Password
MAIN_USER="proxyTest"                       # Main proxy username
MAIN_PASSWORD="it-hub$password"             # Main proxy password
SQUID_CONF="/etc/squid/squid.conf"          # Squid config path
PASSWORD_FILE="/etc/squid/passwords"        # Auth file path
OUTPUT_FILE="squid_proxies.txt"             # Output proxy list
DEFAULT_PORT=7771                           # Squid HTTP port

# Install Squid if not exists
if ! command -v squid &> /dev/null; then
    echo "[+] Installing Squid..."
    sudo apt update
    sudo apt install squid apache2-utils -y
fi

# Backup original config
sudo cp "$SQUID_CONF" "$SQUID_CONF.bak"

# Configure Squid
echo "[+] Configuring Squid..."
{
    echo "http_port $DEFAULT_PORT"

    cat <<EOL
auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASSWORD_FILE
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated

# Deny all other traffic
http_access deny all

# Recommended optimizations
maximum_object_size 256 MB
cache_dir ufs /var/spool/squid 5000 16 256
EOL
} | sudo tee "$SQUID_CONF" > /dev/null

# Generate users and passwords
echo "[+] Generating $NUM_PROXIES proxy users..."
sudo touch "$PASSWORD_FILE"
sudo chown proxy:proxy "$PASSWORD_FILE"
sudo chmod 640 "$PASSWORD_FILE"

> "$OUTPUT_FILE"  # Clear output file

# Add main proxy user
echo "[+] Adding main proxy user..."
echo "$MAIN_USER:$(openssl passwd -apr1 "$MAIN_PASSWORD")" | sudo tee -a "$PASSWORD_FILE" > /dev/null
echo "http://$MAIN_USER:$MAIN_PASSWORD@$MAIN_IP:$DEFAULT_PORT" >> "$OUTPUT_FILE"

# Add additional proxy users
IP_INDEX=0

for ((i=1; i<=NUM_PROXIES; i++)); do
    USERNAME="${PROXY_USER_PREFIX}${i}"
    
    # Add user to Squid auth
    echo "$USERNAME:$(openssl passwd -apr1 "$PROXY_PASSWORD")" | sudo tee -a "$PASSWORD_FILE" > /dev/null
    
    # Assign a unique IP for each proxy
    PROXY_IP="${PROXY_IPS[$IP_INDEX]}"
    
    # Add to proxy list
    echo "http://$USERNAME:$PROXY_PASSWORD@$PROXY_IP:$DEFAULT_PORT" >> "$OUTPUT_FILE"
    
    # Increment IP index
    IP_INDEX=$((IP_INDEX + 1))
done

# Restart Squid
echo "[+] Restarting Squid..."
sudo squid -k parse
sudo systemctl restart squid

# Open firewall port
echo "[+] Opening firewall port $DEFAULT_PORT..."
sudo ufw allow "$DEFAULT_PORT/tcp"

# Output results
echo -e "\n[✅] Generated $((NUM_PROXIES + 1)) Squid HTTP proxies!"
echo -e "[📋] Proxy list saved to: $OUTPUT_FILE\n"
echo "=== Sample Proxies ==="
head -n 5 "$OUTPUT_FILE"
echo "..."
tail -n 5 "$OUTPUT_FILE"