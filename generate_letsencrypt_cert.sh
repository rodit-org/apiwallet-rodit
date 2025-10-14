#!/usr/bin/env bash
# generate_letsencrypt_cert.sh
# Generate Let's Encrypt certificate for a domain using Apache
# Usage: sudo ./generate_letsencrypt_cert.sh <domain> [email]
#
# This script follows the complete procedure for setting up Apache,
# creating virtual hosts, and obtaining Let's Encrypt certificates.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}" >&2
   exit 1
fi

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Usage: sudo $0 <domain> [email]${NC}" >&2
    echo -e "${YELLOW}Example: sudo $0 grafana.cableguard.net admin@cableguard.net${NC}" >&2
    exit 1
fi

DOMAIN="$1"
EMAIL="${2:-}"

echo -e "${BLUE}========== Let's Encrypt Certificate Generation for $DOMAIN ==========${NC}"

# Get server's public IP
echo -e "${YELLOW}Checking server's public IP...${NC}"
IPV4=$(curl -s4 ifconfig.co || echo "Unable to determine")
echo -e "${GREEN}Server public IPv4: $IPV4${NC}"
echo -e "${YELLOW}Ensure DNS A records point $DOMAIN and www.$DOMAIN to this IP${NC}"

# Install Apache2
echo -e "${YELLOW}Installing Apache2...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2

# Configure UFW firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 'Apache Full' || true
    echo -e "${GREEN}Firewall configured for Apache${NC}"
fi

# Disable Apache2 from auto-starting (we'll control it manually)
systemctl disable apache2 || true

# Create web directories
echo -e "${YELLOW}Creating web directories...${NC}"
mkdir -p "/var/www/$DOMAIN"
chown -R www-data:www-data "/var/www/$DOMAIN"
chmod -R 755 "/var/www/$DOMAIN"

# Create index.html
echo -e "${YELLOW}Creating index.html...${NC}"
cat > "/var/www/$DOMAIN/index.html" << EOF
<html>
<head>
    <title>Welcome to $DOMAIN!</title>
</head>
<body>
    <h1>Success! The $DOMAIN virtual host is working!</h1>
    <p>This page confirms that Apache is properly configured for $DOMAIN.</p>
</body>
</html>
EOF

# Create Apache virtual host configuration
echo -e "${YELLOW}Creating Apache virtual host configuration...${NC}"
cat > "/etc/apache2/sites-available/$DOMAIN.conf" << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot /var/www/$DOMAIN
    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
    
    <Directory /var/www/$DOMAIN>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Enable required Apache modules
echo -e "${YELLOW}Enabling Apache modules...${NC}"
a2enmod rewrite >/dev/null 2>&1 || true

# Enable the site
echo -e "${YELLOW}Enabling site configuration...${NC}"
a2ensite "$DOMAIN.conf"

# Disable default site to avoid conflicts
if [ -e /etc/apache2/sites-enabled/000-default.conf ]; then
    a2dissite 000-default.conf || true
fi

# Add ServerName to apache2.conf if not present
if ! grep -q '^ServerName ' /etc/apache2/apache2.conf; then
    echo 'ServerName localhost' >> /etc/apache2/apache2.conf
fi

# Ensure proper Apache configuration
echo -e "${YELLOW}Testing Apache configuration...${NC}"
apache2ctl configtest

# Start Apache
echo -e "${YELLOW}Starting Apache...${NC}"
systemctl start apache2
systemctl reload apache2

# Install Certbot
echo -e "${YELLOW}Installing Certbot...${NC}"
apt-get install -y certbot python3-certbot-apache

# Prepare certbot command
CERTBOT_CMD="certbot --apache -d $DOMAIN -d www.$DOMAIN"

if [ -n "$EMAIL" ]; then
    CERTBOT_CMD="$CERTBOT_CMD --email $EMAIL --agree-tos --non-interactive"
    echo -e "${GREEN}Using email: $EMAIL${NC}"
else
    echo -e "${YELLOW}No email provided. Certbot will prompt for registration.${NC}"
fi

# Run Certbot
echo -e "${YELLOW}Running Certbot to obtain certificate...${NC}"
eval $CERTBOT_CMD

# Check if certificate was created
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
if [ -d "$CERT_PATH" ]; then
    echo -e "${GREEN}Certificate successfully obtained!${NC}"
    echo -e "${GREEN}Certificate files:${NC}"
    echo -e "  ${BLUE}Full chain: $CERT_PATH/fullchain.pem${NC}"
    echo -e "  ${BLUE}Private key: $CERT_PATH/privkey.pem${NC}"
    echo -e "  ${BLUE}Certificate: $CERT_PATH/cert.pem${NC}"
    echo -e "  ${BLUE}Chain: $CERT_PATH/chain.pem${NC}"
    
    # Show certificate details
    echo -e "\n${YELLOW}Certificate details:${NC}"
    openssl x509 -in "$CERT_PATH/cert.pem" -noout -subject -issuer -dates
    
    # Copy certificates to monitoring directory if it exists
    if [ -d "/home/icarus35/monitoring39/certs" ]; then
        echo -e "\n${YELLOW}Copying certificates to monitoring directory...${NC}"
        cp "$CERT_PATH/fullchain.pem" "/home/icarus35/monitoring39/certs/fullchain-$DOMAIN.pem"
        cp "$CERT_PATH/privkey.pem" "/home/icarus35/monitoring39/certs/privkey-$DOMAIN.pem"
        chown icarus35:icarus35 "/home/icarus35/monitoring39/certs/"*"$DOMAIN.pem"
        echo -e "${GREEN}Certificates copied to monitoring directory${NC}"
    fi
else
    echo -e "${RED}Certificate generation failed!${NC}"
    exit 1
fi

# Optional: Stop Apache (uncomment if you want to stop it after certificate generation)
# echo -e "${YELLOW}Stopping Apache...${NC}"
# systemctl stop apache2
# systemctl disable apache2

echo -e "\n${GREEN}========== Certificate Generation Complete ==========${NC}"
echo -e "${GREEN}Domain: $DOMAIN${NC}"
echo -e "${GREEN}Certificate path: $CERT_PATH${NC}"
echo -e "${YELLOW}Note: Apache is still running. Stop it manually if you're using a different web server.${NC}"
echo -e "${YELLOW}To stop Apache: sudo systemctl stop apache2 && sudo systemctl disable apache2${NC}"
