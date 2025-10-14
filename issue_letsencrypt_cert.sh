#!/usr/bin/env bash
# issue_letsencrypt_cert.sh
# Obtain a Let's Encrypt certificate for a domain using Apache temporarily.
# Usage:
#   sudo ./issue_letsencrypt_cert.sh -d example.com [-w] [-e email@example.com]
#
# Options:
#   -d DOMAIN     Required. The domain to issue a certificate for, e.g. grafana.cableguard.net
#   -w            Optional. Also include the www alias (www.DOMAIN)
#   -e EMAIL      Optional. Email to register with Let’s Encrypt (recommended)
#   -n            Non-interactive, agree to TOS and skip prompts (use with -e)
#   -k            Keep Apache enabled and running after issuance (default: stop & disable)
#
# This script will:
#   1) Ensure apache2 and certbot (apache plugin) are installed
#   2) Open firewall for Apache Full (if ufw exists and is active)
#   3) Create a simple Apache vhost on port 80 for DOMAIN (and optional www alias)
#   4) Start Apache, run certbot --apache to obtain cert
#   5) Stop/disable Apache (unless -k is provided)
#
# Resulting certs will be at: /etc/letsencrypt/live/DOMAIN/{fullchain.pem,privkey.pem}
# You can then point your reverse proxy (e.g. Nginx) to these paths, or copy them into your app.

set -euo pipefail

DOMAIN=""
INCLUDE_WWW=false
EMAIL=""
NON_INTERACTIVE=false
KEEP_APACHE=false

while getopts ":d:we:nk" opt; do
  case $opt in
    d) DOMAIN="$OPTARG" ;;
    w) INCLUDE_WWW=true ;;
    e) EMAIL="$OPTARG" ;;
    n) NON_INTERACTIVE=true ;;
    k) KEEP_APACHE=true ;;
    :) echo "Error: -$OPTARG requires a value" >&2; exit 2 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: sudo $0 -d example.com [-w] [-e email@example.com] [-n] [-k]" >&2
  exit 2
fi

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

# Basic DNS check hint
IPV4=$(curl -s4 ifconfig.co || true)
if [[ -n "$IPV4" ]]; then
  echo "Info: Your server public IPv4 appears to be: $IPV4"
  echo "Make sure an A record for $DOMAIN points to this IP before proceeding."
fi

# Install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 certbot python3-certbot-apache

# UFW allow if ufw is active
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -qi "Status: active"; then
    ufw allow 'Apache Full' || true
  fi
fi

# Create webroot and a simple index
WEBROOT="/var/www/$DOMAIN"
mkdir -p "$WEBROOT"
chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"

echo "<html><head><title>Welcome to $DOMAIN</title></head><body><h1>Success! The $DOMAIN virtual host is working!</h1></body></html>" \
  > "$WEBROOT/index.html"

# Create Apache vhost for port 80 only
SITE_CONF="/etc/apache2/sites-available/$DOMAIN.conf"
cat > "$SITE_CONF" <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName $DOMAIN
EOF

if $INCLUDE_WWW; then
  echo "    ServerAlias www.$DOMAIN" >> "$SITE_CONF"
fi

cat >> "$SITE_CONF" <<'EOF'
    DocumentRoot /var/www/REPLACE_DOMAIN
    ErrorLog ${APACHE_LOG_DIR}/REPLACE_DOMAIN-error.log
    CustomLog ${APACHE_LOG_DIR}/REPLACE_DOMAIN-access.log combined

    <Directory /var/www/REPLACE_DOMAIN>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Replace placeholder with actual domain in conf
sed -i "s|REPLACE_DOMAIN|$DOMAIN|g" "$SITE_CONF"

# Enable site and required modules
a2enmod rewrite >/dev/null || true

a2ensite "$DOMAIN.conf"
# Disable default site to avoid conflicts on :80
if [ -e /etc/apache2/sites-enabled/000-default.conf ]; then
  a2dissite 000-default.conf || true
fi

# Set a global ServerName to suppress warnings
if ! grep -q '^ServerName ' /etc/apache2/apache2.conf; then
  echo 'ServerName localhost' >> /etc/apache2/apache2.conf
fi

apache2ctl configtest
systemctl enable --now apache2

# Prepare certbot args
CERTBOT_ARGS=(
  --apache
  -d "$DOMAIN"
)
if $INCLUDE_WWW; then
  CERTBOT_ARGS+=( -d "www.$DOMAIN" )
fi

if $NON_INTERACTIVE; then
  CERTBOT_ARGS+=( -n --agree-tos )
  if [[ -n "$EMAIL" ]]; then
    CERTBOT_ARGS+=( -m "$EMAIL" )
  else
    echo "Non-interactive mode (-n) requires -e EMAIL."
    exit 2
  fi
else
  if [[ -n "$EMAIL" ]]; then
    CERTBOT_ARGS+=( -m "$EMAIL" )
  fi
fi

# Obtain/renew certificate
certbot "${CERTBOT_ARGS[@]}"

# Show resulting paths
LIVE_DIR="/etc/letsencrypt/live/$DOMAIN"
echo "Certificates issued (or renewed). Files:"
echo "  $LIVE_DIR/fullchain.pem"
echo "  $LIVE_DIR/privkey.pem"

# Optionally stop Apache to free ports for your reverse proxy
if ! $KEEP_APACHE; then
  systemctl stop apache2 || true
  systemctl disable apache2 || true
  echo "Apache stopped and disabled."
else
  echo "Apache kept running by request (-k)."
fi

echo "Done. Point your reverse proxy to the cert/key above, or copy/symlink as needed."
