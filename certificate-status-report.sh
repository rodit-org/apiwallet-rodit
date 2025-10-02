#!/bin/bash

# Script: certificate-status-report.sh
# Description: Simple certificate status report for both application and Let's Encrypt certificates
# Usage: ./certificate-status-report.sh [--help]

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help function
show_help() {
    cat << EOF
Certificate Status Report

DESCRIPTION:
    This script provides a simple status report for SSL/TLS certificates from both
    application directories and Let's Encrypt installations. It reports which domains
    are in good standing and which need renewal.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help    Show this help message and exit

WHAT IT REPORTS:
    - Domains with certificates expiring within 30 days (need renewal)
    - Domains with valid certificates (good standing)
    - Missing certificates or keys
    - Certificate/key mismatches

CERTIFICATE SOURCES:
    - Application certificates in various app directories
    - Let's Encrypt certificates in /etc/letsencrypt/live/

EXAMPLES:
    $0              # Run certificate status report
    $0 --help       # Show this help

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    "")
        # No arguments, proceed with normal execution
        ;;
    *)
        echo "Error: Unknown option '$1'"
        echo "Use --help for usage information."
        exit 1
        ;;
esac

echo -e "${BLUE}========== CERTIFICATE STATUS REPORT ==========${NC}"
echo -e "Generated on: $(date)"
echo ""

# Function to check certificate expiry and return status
check_certificate_status() {
    local cert_path="$1"
    local domain_name="$2"
    local use_sudo="$3"
    
    if [ ! -f "$cert_path" ]; then
        echo "MISSING_CERT:$domain_name:::"
        return
    fi
    
    # Get expiry date
    if [ "$use_sudo" = "true" ]; then
        expiry_date=$(sudo openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2-)
    else
        expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2-)
    fi
    
    if [ -z "$expiry_date" ]; then
        echo "INVALID_CERT:$domain_name:::"
        return
    fi
    
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    current_epoch=$(date +%s)
    days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    # Check if key exists and matches
    local key_path
    if [[ "$cert_path" == *"/certs/"* ]]; then
        key_path="$(dirname "$cert_path")/privkey.pem"
    else
        key_path="$(dirname "$cert_path")/privkey.pem"
    fi
    
    local key_status="OK"
    if [ ! -f "$key_path" ]; then
        key_status="MISSING_KEY"
    else
        # Quick key match check
        if [ "$use_sudo" = "true" ]; then
            cert_pubkey_hash=$(sudo openssl x509 -in "$cert_path" -noout -pubkey 2>/dev/null | sudo openssl pkey -pubin -outform DER 2>/dev/null | md5sum | cut -d' ' -f1)
            key_pubkey_hash=$(sudo openssl pkey -in "$key_path" -pubout -outform DER 2>/dev/null | md5sum | cut -d' ' -f1)
        else
            cert_pubkey_hash=$(openssl x509 -in "$cert_path" -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | md5sum | cut -d' ' -f1)
            key_pubkey_hash=$(openssl pkey -in "$key_path" -pubout -outform DER 2>/dev/null | md5sum | cut -d' ' -f1)
        fi
        
        if [ "$cert_pubkey_hash" != "$key_pubkey_hash" ]; then
            key_status="KEY_MISMATCH"
        fi
    fi
    
    # Determine overall status - now include cert and key paths
    if [ $days_remaining -lt 0 ]; then
        echo "EXPIRED:$domain_name:$days_remaining:$key_status:$cert_path:$key_path"
    elif [ $days_remaining -lt 30 ]; then
        echo "NEEDS_RENEWAL:$domain_name:$days_remaining:$key_status:$cert_path:$key_path"
    else
        echo "GOOD:$domain_name:$days_remaining:$key_status:$cert_path:$key_path"
    fi
}

# Arrays to store results
declare -a good_domains=()
declare -a renewal_needed=()
declare -a expired_domains=()
declare -a missing_certs=()
declare -a invalid_certs=()
declare -a key_issues=()

echo -e "${BLUE}Checking Application Certificates...${NC}"

# Application certificate files
APP_CERT_FILES=(
    "/home/icarus35/clienttestapi-app/certs/fullchain.pem"
    "/home/icarus35/clienttestapi-rodit/certs/fullchain.pem"
    "/home/icarus35/mintclientapi-app/certs/fullchain.pem"
    "/home/icarus35/mintclientapi-rodit/certs/fullchain.pem"
    "/home/icarus35/mintdevapi-rodit/certs/fullchain.pem"
    "/home/icarus35/mintdevapi-rodit/src/fullchain.pem"
    "/home/icarus35/mintrootapi-app/certs/fullchain.pem"
    "/home/icarus35/mintrootapi-rodit/certs/fullchain.pem"
    "/home/icarus35/mintserverapi-app/certs/fullchain.pem"
    "/home/icarus35/mintserverapi-rodit/certs/fullchain.pem"
    "/home/icarus35/servertestapi-app/certs/fullchain.pem"
    "/home/icarus35/servertestapi-rodit/certs/fullchain.pem"
    "/home/icarus35/signportal-app/certs/fullchain.pem"
    "/home/icarus35/signportal-rodit/certs/fullchain.pem"
    "/home/icarus35/signsanctum-app/certs/fullchain.pem"
    "/home/icarus35/signsanctum-rodit/certs/fullchain.pem"
)

# Check application certificates
for cert_path in "${APP_CERT_FILES[@]}"; do
    if [ -f "$cert_path" ]; then
        # Extract domain name from path
        domain_name=$(echo "$cert_path" | sed 's|.*/\([^/]*\)/certs/.*|\1|' | sed 's|.*/\([^/]*\)/src/.*|\1|')
        result=$(check_certificate_status "$cert_path" "$domain_name" "false")
        
        IFS=':' read -r status domain days key_status cert_file key_file <<< "$result"
        
        case "$status" in
            "GOOD")
                good_domains+=("$domain ($days days remaining)|$cert_file|$key_file")
                if [ "$key_status" != "OK" ]; then
                    key_issues+=("$domain: $key_status")
                fi
                ;;
            "NEEDS_RENEWAL")
                renewal_needed+=("$domain ($days days remaining)")
                if [ "$key_status" != "OK" ]; then
                    key_issues+=("$domain: $key_status")
                fi
                ;;
            "EXPIRED")
                expired_domains+=("$domain (expired $((0-days)) days ago)")
                ;;
            "MISSING_CERT")
                missing_certs+=("$domain (application)")
                ;;
            "INVALID_CERT")
                invalid_certs+=("$domain (application)")
                ;;
        esac
    fi
done

echo -e "${BLUE}Checking Let's Encrypt Certificates...${NC}"

# Check Let's Encrypt certificates (if accessible)
if [ -d "/etc/letsencrypt/live/" ]; then
    # Get list of domains from /etc/letsencrypt/live/
    while IFS= read -r -d '' domain_dir; do
        domain=$(basename "$domain_dir")
        
        # Skip README
        if [ "$domain" == "README" ]; then
            continue
        fi
        
        cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        result=$(check_certificate_status "$cert_path" "$domain" "true")
        
        IFS=':' read -r status domain_name days key_status cert_file key_file <<< "$result"
        
        case "$status" in
            "GOOD")
                good_domains+=("$domain_name ($days days remaining) [LE]|$cert_file|$key_file")
                if [ "$key_status" != "OK" ]; then
                    key_issues+=("$domain_name: $key_status [LE]")
                fi
                ;;
            "NEEDS_RENEWAL")
                renewal_needed+=("$domain_name ($days days remaining) [LE]")
                if [ "$key_status" != "OK" ]; then
                    key_issues+=("$domain_name: $key_status [LE]")
                fi
                ;;
            "EXPIRED")
                expired_domains+=("$domain_name (expired $((0-days)) days ago) [LE]")
                ;;
            "MISSING_CERT")
                missing_certs+=("$domain_name [LE]")
                ;;
            "INVALID_CERT")
                invalid_certs+=("$domain_name [LE]")
                ;;
        esac
    done < <(find /etc/letsencrypt/live/ -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
else
    echo -e "${YELLOW}Let's Encrypt directory not accessible or not found${NC}"
fi

echo ""
echo -e "${BLUE}========== CERTIFICATE STATUS SUMMARY ==========${NC}"

# Report good domains
if [ ${#good_domains[@]} -gt 0 ]; then
    echo -e "\n${GREEN}✓ DOMAINS IN GOOD STANDING (${#good_domains[@]}):${NC}"
    for domain_info in "${good_domains[@]}"; do
        IFS='|' read -r domain_desc cert_path key_path <<< "$domain_info"
        echo -e "  ${GREEN}✓${NC} $domain_desc"
        echo -e "    Certificate: $cert_path"
        echo -e "    Private Key: $key_path"
        echo ""
    done
fi

# Report domains needing renewal
if [ ${#renewal_needed[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}⚠ DOMAINS NEEDING RENEWAL (${#renewal_needed[@]}):${NC}"
    for domain in "${renewal_needed[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} $domain"
    done
fi

# Report expired domains
if [ ${#expired_domains[@]} -gt 0 ]; then
    echo -e "\n${RED}✗ EXPIRED DOMAINS (${#expired_domains[@]}):${NC}"
    for domain in "${expired_domains[@]}"; do
        echo -e "  ${RED}✗${NC} $domain"
    done
fi

# Report missing certificates
if [ ${#missing_certs[@]} -gt 0 ]; then
    echo -e "\n${RED}✗ MISSING CERTIFICATES (${#missing_certs[@]}):${NC}"
    for domain in "${missing_certs[@]}"; do
        echo -e "  ${RED}✗${NC} $domain"
    done
fi

# Report invalid certificates
if [ ${#invalid_certs[@]} -gt 0 ]; then
    echo -e "\n${RED}✗ INVALID CERTIFICATES (${#invalid_certs[@]}):${NC}"
    for domain in "${invalid_certs[@]}"; do
        echo -e "  ${RED}✗${NC} $domain"
    done
fi

# Report key issues
if [ ${#key_issues[@]} -gt 0 ]; then
    echo -e "\n${RED}✗ KEY ISSUES (${#key_issues[@]}):${NC}"
    for issue in "${key_issues[@]}"; do
        echo -e "  ${RED}✗${NC} $issue"
    done
fi

# Overall summary
echo -e "\n${BLUE}========== OVERALL SUMMARY ==========${NC}"
total_domains=$((${#good_domains[@]} + ${#renewal_needed[@]} + ${#expired_domains[@]} + ${#missing_certs[@]} + ${#invalid_certs[@]}))
echo -e "Total domains examined: $total_domains"
echo -e "${GREEN}Good standing: ${#good_domains[@]}${NC}"
echo -e "${YELLOW}Need renewal: ${#renewal_needed[@]}${NC}"
echo -e "${RED}Expired: ${#expired_domains[@]}${NC}"
echo -e "${RED}Missing/Invalid: $((${#missing_certs[@]} + ${#invalid_certs[@]}))${NC}"
echo -e "${RED}Key issues: ${#key_issues[@]}${NC}"

# Exit with appropriate code
if [ ${#renewal_needed[@]} -gt 0 ] || [ ${#expired_domains[@]} -gt 0 ] || [ ${#missing_certs[@]} -gt 0 ] || [ ${#invalid_certs[@]} -gt 0 ] || [ ${#key_issues[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}⚠ Action required for some certificates${NC}"
    exit 1
else
    echo -e "\n${GREEN}✓ All certificates are in good standing${NC}"
    exit 0
fi
