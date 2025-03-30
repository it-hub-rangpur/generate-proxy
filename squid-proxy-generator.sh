#!/bin/bash

# Configuration
PROXY_IP=$(hostname -I | awk '{print $1}')  # Your server's main IP
START_PORT=5000                             # Starting port for proxies
NUM_PROXIES=500                             # Number of proxies to generate
PROXY_USER_PREFIX="ithub"                   # Username prefix
PROXY_PASSWORD="it-hub$password"            # Password
SQUID_CONF="/etc/squid/squid.conf"          # Squid config path
PASSWORD_FILE="/etc/squid/passwords"        # Auth file path
OUTPUT_FILE="squid_proxies.txt"             # Output proxy list

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
sudo tee "$SQUID_CONF" > /dev/null <<EOL
http_port $START_PORT-$((START_PORT + NUM_PROXIES - 1))

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

# Generate users and passwords
echo "[+] Generating $NUM_PROXIES proxy users..."
sudo touch "$PASSWORD_FILE"
sudo chown proxy:proxy "$PASSWORD_FILE"
sudo chmod 640 "$PASSWORD_FILE"

> "$OUTPUT_FILE"  # Clear output file

for ((i=1; i<=NUM_PROXIES; i++)); do
    PORT=$((START_PORT + i - 1))
    USERNAME="${PROXY_USER_PREFIX}${i}"
    
    # Add user to Squid auth
    echo "$USERNAME:$(openssl passwd -apr1 "$PROXY_PASSWORD")" | sudo tee -a "$PASSWORD_FILE" > /dev/null
    
    # Add to proxy list
    echo "http://$USERNAME:$PROXY_PASSWORD@$PROXY_IP:$PORT" >> "$OUTPUT_FILE"
done

# Restart Squid
echo "[+] Restarting Squid..."
sudo squid -k parse
sudo systemctl restart squid

# Open firewall ports
echo "[+] Opening firewall ports $START_PORT-$((START_PORT + NUM_PROXIES - 1))..."
sudo ufw allow "$START_PORT:$((START_PORT + NUM_PROXIES - 1))/tcp"

# Output results
echo -e "\n[✅] Generated $NUM_PROXIES Squid proxies!"
echo -e "[📋] Proxy list saved to: $OUTPUT_FILE\n"
echo "=== Sample Proxies ==="
head -n 5 "$OUTPUT_FILE"
echo "..."
tail -n 5 "$OUTPUT_FILE"