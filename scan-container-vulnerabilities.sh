#!/bin/bash

# Script: scan-container-vulnerabilities.sh
# Description: Comprehensive container vulnerability scanning using Trivy
# Usage: ./scan-container-vulnerabilities.sh [--help]

set -e

# Help function
show_help() {
    cat << EOF
Container Vulnerability Scanner

DESCRIPTION:
    This script performs comprehensive security vulnerability scanning of all Podman 
    containers using Trivy. It identifies HIGH and CRITICAL severity vulnerabilities
    in container images and generates detailed reports.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help    Show this help message and exit

WHAT IT SCANS:
    - All unique container images from 'podman ps -a'
    - HIGH and CRITICAL severity vulnerabilities only
    - Operating system packages and libraries
    - Application dependencies and frameworks

FEATURES:
    - Automatic unique image detection from Podman containers
    - Timestamped scan reports in ./trivy-scan-results/
    - Detailed vulnerability information in table format
    - JSON summary reports for automation (if jq is available)
    - Scan statistics and success/failure tracking
    - Quick vulnerability summary display

OUTPUT FILES:
    - Text Report: ./trivy-scan-results/trivy-scan-report-YYYYMMDD_HHMMSS.txt
    - JSON Summary: ./trivy-scan-results/trivy-summary-YYYYMMDD_HHMMSS.json

REQUIREMENTS:
    - Trivy security scanner installed
    - Podman container runtime
    - Access to container images
    - Optional: jq for JSON report generation

EXAMPLES:
    $0              # Scan all container images for vulnerabilities
    $0 --help       # Show this help

NOTE:
    This script focuses on HIGH and CRITICAL vulnerabilities only to reduce noise.
    Results are saved to timestamped files for historical tracking.

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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCAN_RESULTS_DIR="./trivy-scan-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$SCAN_RESULTS_DIR/trivy-scan-report-$TIMESTAMP.txt"

# Create results directory
mkdir -p "$SCAN_RESULTS_DIR"

echo -e "${BLUE}=== Trivy Container Security Scan Report ===${NC}"
echo -e "${BLUE}Timestamp: $(date)${NC}"
echo -e "${BLUE}Results will be saved to: $REPORT_FILE${NC}"
echo ""

# Initialize report file
{
    echo "=== Trivy Container Security Scan Report ==="
    echo "Timestamp: $(date)"
    echo "=========================================="
    echo ""
} > "$REPORT_FILE"

# Get unique images from podman ps -a
echo -e "${YELLOW}Extracting unique images from Podman containers...${NC}"
IMAGES=$(podman ps -a --format "{{.Image}}" | sort | uniq | grep -v "^$")

# Counter for summary
TOTAL_IMAGES=0
SCANNED_IMAGES=0
FAILED_SCANS=0

echo -e "${BLUE}Found the following unique images:${NC}"
echo "$IMAGES"
echo ""

# Scan each unique image
for IMAGE in $IMAGES; do
    TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
    
    echo -e "${YELLOW}Scanning image: $IMAGE${NC}"
    echo "----------------------------------------"
    
    # Add to report
    {
        echo "=== Scanning: $IMAGE ==="
        echo "Scan started: $(date)"
        echo ""
    } >> "$REPORT_FILE"
    
    # Run Trivy scan
    if trivy image --severity HIGH,CRITICAL --format table "$IMAGE" 2>&1 | tee -a "$REPORT_FILE"; then
        echo -e "${GREEN}✓ Scan completed for $IMAGE${NC}"
        SCANNED_IMAGES=$((SCANNED_IMAGES + 1))
    else
        echo -e "${RED}✗ Scan failed for $IMAGE${NC}"
        FAILED_SCANS=$((FAILED_SCANS + 1))
        echo "ERROR: Failed to scan $IMAGE" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "----------------------------------------" >> "$REPORT_FILE"
    echo ""
    
    # Small delay to avoid overwhelming the system
    sleep 1
done

# Summary
echo -e "${BLUE}=== Scan Summary ===${NC}"
echo -e "Total images found: $TOTAL_IMAGES"
echo -e "Successfully scanned: ${GREEN}$SCANNED_IMAGES${NC}"
echo -e "Failed scans: ${RED}$FAILED_SCANS${NC}"
echo -e "Report saved to: ${BLUE}$REPORT_FILE${NC}"

# Add summary to report
{
    echo ""
    echo "=== SCAN SUMMARY ==="
    echo "Total images found: $TOTAL_IMAGES"
    echo "Successfully scanned: $SCANNED_IMAGES"
    echo "Failed scans: $FAILED_SCANS"
    echo "Scan completed: $(date)"
} >> "$REPORT_FILE"

# Optional: Generate JSON report for automation
if command -v jq &> /dev/null; then
    echo -e "${YELLOW}Generating JSON summary report...${NC}"
    JSON_REPORT="$SCAN_RESULTS_DIR/trivy-summary-$TIMESTAMP.json"
    
    # Create a simple JSON summary
    cat > "$JSON_REPORT" << EOF
{
    "scan_timestamp": "$(date -Iseconds)",
    "total_images": $TOTAL_IMAGES,
    "scanned_images": $SCANNED_IMAGES,
    "failed_scans": $FAILED_SCANS,
    "images_scanned": [
$(echo "$IMAGES" | sed 's/^/        "/' | sed 's/$/"/' | sed '$!s/$/,/')
    ],
    "report_file": "$REPORT_FILE"
}
EOF
    echo -e "JSON summary saved to: ${BLUE}$JSON_REPORT${NC}"
fi

echo -e "${GREEN}Scan complete! Check the report file for detailed results.${NC}"

# Optional: Show high-level summary of vulnerabilities found
echo -e "\n${YELLOW}Quick vulnerability summary:${NC}"
if grep -q "Total:" "$REPORT_FILE"; then
    grep "Total:" "$REPORT_FILE" | head -10
else
    echo "No vulnerability summary found in basic scan."
fi
