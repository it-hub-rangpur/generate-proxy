#!/bin/bash

# Configuration
PROXY_IP=$(curl -s ifconfig.me)             # Your server's public IP
NUM_PROXIES=500                             # Number of proxies to generate
PROXY_USER_PREFIX="ithub"                   # Username prefix
PROXY_PASSWORD="it-hub$password"            # Password
SQUID_CONF="/etc/squid/squid.conf"          # Squid config path
PASSWORD_FILE="/etc/squid/passwords"        # Auth file path
OUTPUT_FILE="squid_https_proxies.txt"       # Output proxy list
DEFAULT_PORT=3128                           # Squid HTTPS port
SSL_CERT_DIR="/etc/squid/ssl_cert"          # SSL certificate directory

# Install Squid if not exists
if ! command -v squid &> /dev/null; then
    echo "[+] Installing Squid..."
    sudo apt update
    sudo apt install squid apache2-utils -y
fi

# Generate SSL certificates
echo "[+] Generating SSL certificates..."
sudo mkdir -p "$SSL_CERT_DIR"
cd "$SSL_CERT_DIR"
sudo openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -keyout squid.key -out squid.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=$PROXY_IP"
sudo cat squid.key squid.crt | sudo tee squid.pem
sudo chmod 600 squid.pem

# Backup original config
sudo cp "$SQUID_CONF" "$SQUID_CONF.bak"

# Configure Squid
echo "[+] Configuring Squid..."
{
    echo "http_port 3128 ssl-bump cert=$SSL_CERT_DIR/squid.pem key=$SSL_CERT_DIR/squid.key"
    echo "https_port $DEFAULT_PORT cert=$SSL_CERT_DIR/squid.pem key=$SSL_CERT_DIR/squid.key"

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

# SSL Bump configuration
acl step1 at_step SslBump1
ssl_bump peek step1
ssl_bump bump all
EOL
} | sudo tee "$SQUID_CONF" > /dev/null

# Generate users and passwords
echo "[+] Generating $NUM_PROXIES proxy users..."
sudo touch "$PASSWORD_FILE"
sudo chown proxy:proxy "$PASSWORD_FILE"
sudo chmod 640 "$PASSWORD_FILE"

> "$OUTPUT_FILE"  # Clear output file

for ((i=1; i<=NUM_PROXIES; i++)); do
    USERNAME="${PROXY_USER_PREFIX}${i}"
    
    # Add user to Squid auth
    echo "$USERNAME:$(openssl passwd -apr1 "$PROXY_PASSWORD")" | sudo tee -a "$PASSWORD_FILE" > /dev/null
    
    # Add to proxy list
    echo "https://$USERNAME:$PROXY_PASSWORD@$PROXY_IP:$DEFAULT_PORT" >> "$OUTPUT_FILE"
done

# Restart Squid
echo "[+] Restarting Squid..."
sudo squid -k parse
sudo systemctl restart squid

# Open firewall port
echo "[+] Opening firewall port $DEFAULT_PORT..."
sudo ufw allow "$DEFAULT_PORT/tcp"

# Output results
echo -e "\n[✅] Generated $NUM_PROXIES Squid HTTPS proxies!"
echo -e "[📋] Proxy list saved to: $OUTPUT_FILE\n"
echo "=== Sample Proxies ==="
head -n 5 "$OUTPUT_FILE"
echo "..."
tail -n 5 "$OUTPUT_FILE"