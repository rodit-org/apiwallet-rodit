#!/usr/bin/env bash
# create_letsencrypt_cert.sh
# Reusable script to generate Let's Encrypt certificates for any domain
# Usage: sudo ./create_letsencrypt_cert.sh <domain> [options]
#
# Options:
#   -e EMAIL      Email for Let's Encrypt registration
#   -w            Include www subdomain (requires www DNS record)
#   -k            Keep Apache running after certificate generation
#   -n            Non-interactive mode (requires -e)
#   -s            Stop Apache after certificate generation (default)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default options
DOMAIN=""
EMAIL=""
INCLUDE_WWW=false
KEEP_APACHE=false
NON_INTERACTIVE=false
STOP_APACHE=true

# Parse arguments
while getopts "e:wkns" opt; do
    case $opt in
        e) EMAIL="$OPTARG" ;;
        w) INCLUDE_WWW=true ;;
        k) KEEP_APACHE=true; STOP_APACHE=false ;;
        n) NON_INTERACTIVE=true ;;
        s) STOP_APACHE=true; KEEP_APACHE=false ;;
        \?) echo -e "${RED}Invalid option: -$OPTARG${NC}" >&2; exit 1 ;;
    esac
done

shift $((OPTIND-1))
DOMAIN="$1"

# Validation
if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Usage: sudo $0 <domain> [-e email] [-w] [-k] [-n] [-s]${NC}" >&2
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  ${BLUE}sudo $0 grafana.cableguard.net${NC}"
    echo -e "  ${BLUE}sudo $0 api.example.com -e admin@example.com -w${NC}"
    echo -e "  ${BLUE}sudo $0 monitor.site.com -e admin@site.com -n -k${NC}"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root (use sudo)${NC}" >&2
    exit 1
fi

if [[ "$NON_INTERACTIVE" == true && -z "$EMAIL" ]]; then
    echo -e "${RED}Non-interactive mode (-n) requires email (-e)${NC}" >&2
    exit 1
fi

echo -e "${BLUE}========== Let's Encrypt Certificate for $DOMAIN ==========${NC}"

# Check server IP and DNS
IPV4=$(curl -s4 ifconfig.co || echo "Unable to determine")
echo -e "${GREEN}Server public IPv4: $IPV4${NC}"
if [[ "$INCLUDE_WWW" == true ]]; then
    echo -e "${YELLOW}Ensure DNS A records: $DOMAIN and www.$DOMAIN → $IPV4${NC}"
else
    echo -e "${YELLOW}Ensure DNS A record: $DOMAIN → $IPV4${NC}"
fi

# Install dependencies
echo -e "${YELLOW}Installing Apache2 and Certbot...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y apache2 certbot python3-certbot-apache >/dev/null 2>&1

# Configure firewall
if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi "Status: active"; then
    ufw allow 'Apache Full' >/dev/null 2>&1 || true
fi

# Create web directory and content
mkdir -p "/var/www/$DOMAIN"
chown -R www-data:www-data "/var/www/$DOMAIN"
chmod -R 755 "/var/www/$DOMAIN"

cat > "/var/www/$DOMAIN/index.html" << EOF
<html>
<head><title>Welcome to $DOMAIN!</title></head>
<body><h1>Success! The $DOMAIN virtual host is working!</h1></body>
</html>
EOF

# Create Apache virtual host
cat > "/etc/apache2/sites-available/$DOMAIN.conf" << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName $DOMAIN
EOF

if [[ "$INCLUDE_WWW" == true ]]; then
    echo "    ServerAlias www.$DOMAIN" >> "/etc/apache2/sites-available/$DOMAIN.conf"
fi

cat >> "/etc/apache2/sites-available/$DOMAIN.conf" << EOF
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

# Configure Apache
a2enmod rewrite >/dev/null 2>&1 || true
a2ensite "$DOMAIN.conf" >/dev/null 2>&1
a2dissite 000-default.conf >/dev/null 2>&1 || true

# Add ServerName if missing
if ! grep -q '^ServerName ' /etc/apache2/apache2.conf; then
    echo 'ServerName localhost' >> /etc/apache2/apache2.conf
fi

# Test and start Apache
apache2ctl configtest >/dev/null 2>&1
systemctl start apache2
systemctl reload apache2

# Build certbot command
CERTBOT_CMD="certbot --apache -d $DOMAIN"
if [[ "$INCLUDE_WWW" == true ]]; then
    CERTBOT_CMD="$CERTBOT_CMD -d www.$DOMAIN"
fi

if [[ "$NON_INTERACTIVE" == true ]]; then
    CERTBOT_CMD="$CERTBOT_CMD --agree-tos --non-interactive --email $EMAIL"
elif [[ -n "$EMAIL" ]]; then
    CERTBOT_CMD="$CERTBOT_CMD --agree-tos --non-interactive --email $EMAIL"
else
    CERTBOT_CMD="$CERTBOT_CMD --register-unsafely-without-email"
fi

# Generate certificate
echo -e "${YELLOW}Generating certificate...${NC}"
if eval $CERTBOT_CMD >/dev/null 2>&1; then
    echo -e "${GREEN}Certificate successfully generated!${NC}"
    
    # Show certificate info
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    echo -e "${GREEN}Certificate files:${NC}"
    echo -e "  ${BLUE}Full chain: $CERT_PATH/fullchain.pem${NC}"
    echo -e "  ${BLUE}Private key: $CERT_PATH/privkey.pem${NC}"
    
    # Copy to monitoring directory if it exists
    if [[ -d "/home/icarus35/monitoring39/certs" ]]; then
        cp "$CERT_PATH/fullchain.pem" "/home/icarus35/monitoring39/certs/fullchain-$DOMAIN.pem"
        cp "$CERT_PATH/privkey.pem" "/home/icarus35/monitoring39/certs/privkey-$DOMAIN.pem"
        chown icarus35:icarus35 "/home/icarus35/monitoring39/certs/"*"$DOMAIN.pem"
        echo -e "${GREEN}Certificates copied to monitoring directory${NC}"
    fi
    
    # Show expiration
    EXPIRY=$(openssl x509 -in "$CERT_PATH/cert.pem" -noout -enddate | cut -d= -f2)
    echo -e "${GREEN}Certificate expires: $EXPIRY${NC}"
    
else
    echo -e "${RED}Certificate generation failed!${NC}"
    echo -e "${YELLOW}Check DNS records and try again${NC}"
    exit 1
fi

# Handle Apache service
if [[ "$STOP_APACHE" == true ]]; then
    systemctl stop apache2
    systemctl disable apache2 >/dev/null 2>&1 || true
    echo -e "${YELLOW}Apache stopped and disabled${NC}"
elif [[ "$KEEP_APACHE" == true ]]; then
    echo -e "${GREEN}Apache kept running${NC}"
fi

echo -e "${GREEN}========== Certificate Generation Complete ==========${NC}"
