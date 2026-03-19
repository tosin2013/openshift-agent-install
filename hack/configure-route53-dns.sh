#!/bin/bash
# configure-route53-dns.sh - Manage Route53 DNS records for OpenShift clusters
# This script creates/removes A records in AWS Route53 for external access

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_status() {
    if [ $2 -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        exit 1
    fi
}

print_section() {
    echo -e "\n${YELLOW}$1${NC}"
    echo "================================"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"

    # Check for AWS CLI
    if ! command -v aws &>/dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI."
        echo ""
        echo "Install with:"
        echo "  curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\""
        echo "  unzip awscliv2.zip"
        echo "  sudo ./aws/install"
        exit 1
    fi
    print_status "AWS CLI is installed" 0

    # Check for yq
    if ! command -v yq &>/dev/null; then
        print_error "yq not found. Please install yq for YAML parsing."
        echo "Install with: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
        exit 1
    fi
    print_status "yq is installed" 0

    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "AWS credentials not configured or invalid"
        echo ""
        echo "Please configure AWS credentials:"
        echo "  export AWS_ACCESS_KEY_ID=\"your-key-id\""
        echo "  export AWS_SECRET_ACCESS_KEY=\"your-secret-key\""
        echo ""
        echo "Or run: aws configure"
        exit 1
    fi
    print_status "AWS credentials are valid" 0

    # Check for EXTERNAL_IP environment variable
    if [ -z "$EXTERNAL_IP" ]; then
        print_error "EXTERNAL_IP environment variable is not set"
        echo ""
        echo "Please set your host's external/public IP address:"
        echo "  export EXTERNAL_IP=\"203.0.113.10\""
        exit 1
    fi

    # Validate EXTERNAL_IP format
    if ! [[ $EXTERNAL_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "EXTERNAL_IP is not a valid IP address: ${EXTERNAL_IP}"
        exit 1
    fi
    print_status "EXTERNAL_IP is set: ${EXTERNAL_IP}" 0
}

# Function to parse cluster configuration
parse_cluster_config() {
    local cluster_config=$1

    print_section "Parsing Cluster Configuration"

    if [ ! -f "$cluster_config" ]; then
        print_error "Cluster configuration file not found: ${cluster_config}"
        exit 1
    fi

    print_info "Reading: ${cluster_config}"

    # Parse cluster.yml using yq
    CLUSTER_NAME=$(yq eval '.cluster_name' "$cluster_config")
    BASE_DOMAIN=$(yq eval '.base_domain' "$cluster_config")

    # Validate required fields
    if [ "$CLUSTER_NAME" == "null" ] || [ -z "$CLUSTER_NAME" ]; then
        print_error "cluster_name not found in ${cluster_config}"
        exit 1
    fi

    if [ "$BASE_DOMAIN" == "null" ] || [ -z "$BASE_DOMAIN" ]; then
        print_error "base_domain not found in ${cluster_config}"
        exit 1
    fi

    print_info "Cluster: ${CLUSTER_NAME}.${BASE_DOMAIN}"

    # Warn if domain looks like a test/invalid domain
    if [[ "$BASE_DOMAIN" =~ ^(example\.(com|org|net)|.*\.local|test|localhost)$ ]]; then
        echo ""
        print_error "WARNING: base_domain '${BASE_DOMAIN}' appears to be a test/local domain"
        echo ""
        echo "Route53 requires a REAL domain that you own. Common test domains will fail:"
        echo "  - example.com / example.org / example.net (reserved for documentation)"
        echo "  - *.local (mDNS/local networks only)"
        echo "  - test / localhost (not valid public domains)"
        echo ""
        echo "You must use a domain you own with a Route53 hosted zone."
        echo "Press Ctrl+C to cancel, or Enter to continue anyway..."
        read -r
    fi

    print_status "Configuration parsed successfully" 0
}

# Function to get Route53 hosted zone ID
get_hosted_zone_id() {
    print_section "Finding Route53 Hosted Zone"

    # Check if ROUTE53_HOSTED_ZONE_ID is already set
    if [ -n "$ROUTE53_HOSTED_ZONE_ID" ]; then
        print_info "Using provided ROUTE53_HOSTED_ZONE_ID: ${ROUTE53_HOSTED_ZONE_ID}"
        ZONE_ID="$ROUTE53_HOSTED_ZONE_ID"
        print_status "Hosted zone ID configured" 0
        return
    fi

    print_info "Looking for hosted zone: ${BASE_DOMAIN}"

    # Query Route53 for hosted zone
    ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${BASE_DOMAIN}.'].Id" --output text 2>/dev/null | sed 's|/hostedzone/||')

    if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "None" ]; then
        print_error "No Route53 hosted zone found for ${BASE_DOMAIN}"
        echo ""
        echo "Please ensure:"
        echo "  1. A Route53 hosted zone exists for ${BASE_DOMAIN}"
        echo "  2. Your AWS credentials have access to Route53"
        echo ""
        echo "Or provide the zone ID manually:"
        echo "  export ROUTE53_HOSTED_ZONE_ID=\"Z1234567890ABC\""
        exit 1
    fi

    print_info "Found hosted zone ID: ${ZONE_ID}"
    print_status "Hosted zone located" 0
}

# Function to add DNS records
add_dns_records() {
    local cluster_config=$1

    check_prerequisites
    parse_cluster_config "$cluster_config"
    get_hosted_zone_id

    print_section "Adding Route53 DNS Records"

    # Create JSON change batch for Route53
    CHANGE_BATCH=$(cat << EOF
{
  "Comment": "DNS records for OpenShift cluster ${CLUSTER_NAME}.${BASE_DOMAIN}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.${CLUSTER_NAME}.${BASE_DOMAIN}",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "${EXTERNAL_IP}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "${EXTERNAL_IP}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "${EXTERNAL_IP}"}]
      }
    }
  ]
}
EOF
)

    print_info "Creating DNS records (all pointing to ${EXTERNAL_IP})..."
    print_info "  api.${CLUSTER_NAME}.${BASE_DOMAIN}"
    print_info "  api-int.${CLUSTER_NAME}.${BASE_DOMAIN}"
    print_info "  *.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"

    # Apply changes to Route53
    CHANGE_ID=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --change-batch "$CHANGE_BATCH" \
        --query 'ChangeInfo.Id' \
        --output text 2>&1)

    if [ $? -eq 0 ]; then
        print_status "DNS records created successfully" 0
        print_info "Change ID: ${CHANGE_ID}"
    else
        print_error "Failed to create DNS records"
        echo "$CHANGE_ID"
        exit 1
    fi

    print_section "DNS Records Added"
    echo ""
    echo -e "${GREEN}Route53 DNS records configured:${NC}"
    echo "  api.${CLUSTER_NAME}.${BASE_DOMAIN} → ${EXTERNAL_IP}"
    echo "  api-int.${CLUSTER_NAME}.${BASE_DOMAIN} → ${EXTERNAL_IP}"
    echo "  *.apps.${CLUSTER_NAME}.${BASE_DOMAIN} → ${EXTERNAL_IP}"
    echo ""
    echo "DNS propagation may take a few minutes. Test with:"
    echo "  dig api.${CLUSTER_NAME}.${BASE_DOMAIN} +short"
    echo "  dig test.apps.${CLUSTER_NAME}.${BASE_DOMAIN} +short"
}

# Function to remove DNS records
remove_dns_records() {
    local cluster_config=$1

    check_prerequisites
    parse_cluster_config "$cluster_config"
    get_hosted_zone_id

    print_section "Removing Route53 DNS Records"

    # First, get the current records to delete them properly
    print_info "Retrieving current DNS records..."

    # Get API record
    API_RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --query "ResourceRecordSets[?Name=='api.${CLUSTER_NAME}.${BASE_DOMAIN}.']" \
        --output json 2>/dev/null)

    # Get API-INT record
    API_INT_RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --query "ResourceRecordSets[?Name=='api-int.${CLUSTER_NAME}.${BASE_DOMAIN}.']" \
        --output json 2>/dev/null)

    # Get wildcard apps record
    APPS_RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --query "ResourceRecordSets[?Name=='\\052.apps.${CLUSTER_NAME}.${BASE_DOMAIN}.']" \
        --output json 2>/dev/null)

    # Build delete change batch
    CHANGES=""

    if [ "$API_RECORD" != "[]" ] && [ -n "$API_RECORD" ]; then
        API_IP=$(echo "$API_RECORD" | jq -r '.[0].ResourceRecords[0].Value')
        API_TTL=$(echo "$API_RECORD" | jq -r '.[0].TTL')
        CHANGES="${CHANGES}{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"api.${CLUSTER_NAME}.${BASE_DOMAIN}\",\"Type\":\"A\",\"TTL\":${API_TTL},\"ResourceRecords\":[{\"Value\":\"${API_IP}\"}]}},"
        print_info "Found api.${CLUSTER_NAME}.${BASE_DOMAIN} → ${API_IP}"
    fi

    if [ "$API_INT_RECORD" != "[]" ] && [ -n "$API_INT_RECORD" ]; then
        API_INT_IP=$(echo "$API_INT_RECORD" | jq -r '.[0].ResourceRecords[0].Value')
        API_INT_TTL=$(echo "$API_INT_RECORD" | jq -r '.[0].TTL')
        CHANGES="${CHANGES}{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"api-int.${CLUSTER_NAME}.${BASE_DOMAIN}\",\"Type\":\"A\",\"TTL\":${API_INT_TTL},\"ResourceRecords\":[{\"Value\":\"${API_INT_IP}\"}]}},"
        print_info "Found api-int.${CLUSTER_NAME}.${BASE_DOMAIN} → ${API_INT_IP}"
    fi

    if [ "$APPS_RECORD" != "[]" ] && [ -n "$APPS_RECORD" ]; then
        APPS_IP=$(echo "$APPS_RECORD" | jq -r '.[0].ResourceRecords[0].Value')
        APPS_TTL=$(echo "$APPS_RECORD" | jq -r '.[0].TTL')
        CHANGES="${CHANGES}{\"Action\":\"DELETE\",\"ResourceRecordSet\":{\"Name\":\"*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}\",\"Type\":\"A\",\"TTL\":${APPS_TTL},\"ResourceRecords\":[{\"Value\":\"${APPS_IP}\"}]}},"
        print_info "Found *.apps.${CLUSTER_NAME}.${BASE_DOMAIN} → ${APPS_IP}"
    fi

    # Remove trailing comma
    CHANGES="${CHANGES%,}"

    if [ -z "$CHANGES" ]; then
        print_info "No DNS records found to remove"
        print_status "Nothing to remove" 0
        return
    fi

    # Create change batch
    CHANGE_BATCH="{\"Comment\":\"Remove DNS records for ${CLUSTER_NAME}.${BASE_DOMAIN}\",\"Changes\":[${CHANGES}]}"

    print_info "Removing DNS records..."

    # Apply changes to Route53
    CHANGE_ID=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --change-batch "$CHANGE_BATCH" \
        --query 'ChangeInfo.Id' \
        --output text 2>&1)

    if [ $? -eq 0 ]; then
        print_status "DNS records removed successfully" 0
        print_info "Change ID: ${CHANGE_ID}"
    else
        print_error "Failed to remove DNS records"
        echo "$CHANGE_ID"
        exit 1
    fi

    print_section "DNS Records Removed"
    echo -e "${GREEN}Route53 DNS records have been deleted${NC}"
}

# Function to list DNS records
list_dns_records() {
    local cluster_config=$1

    check_prerequisites
    parse_cluster_config "$cluster_config"
    get_hosted_zone_id

    print_section "Current Route53 DNS Records"

    print_info "Listing records for ${CLUSTER_NAME}.${BASE_DOMAIN}..."
    echo ""

    # List all A records for this cluster
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --query "ResourceRecordSets[?contains(Name, '${CLUSTER_NAME}.${BASE_DOMAIN}') && Type=='A'].[Name, Type, TTL, ResourceRecords[0].Value]" \
        --output table

    print_status "DNS records listed" 0
}

# Usage function
usage() {
    cat << EOF
Usage: $0 {add|remove|list} <cluster_config.yml>

Manage Route53 DNS records for OpenShift external access.

Commands:
  add <cluster_config.yml>     Add DNS records to Route53
  remove <cluster_config.yml>  Remove DNS records from Route53
  list <cluster_config.yml>    List current DNS records

Prerequisites:
  - AWS CLI installed and configured
  - yq installed for YAML parsing
  - AWS credentials with Route53 permissions
  - EXTERNAL_IP environment variable set
  - Route53 hosted zone for base_domain

IMPORTANT - Domain Requirements:
  The base_domain in cluster.yml MUST be a real domain you own with a
  Route53 hosted zone. Test domains like "example.com" or "lab.local"
  will NOT work. Both local dnsmasq and external Route53 use the SAME
  domain names but resolve to different IPs (VIPs vs EXTERNAL_IP).

Example:
  export AWS_ACCESS_KEY_ID="your-key-id"
  export AWS_SECRET_ACCESS_KEY="your-secret-key"
  export EXTERNAL_IP="203.0.113.10"

  $0 add examples/sno-4.20-standard/cluster.yml
  $0 list examples/sno-4.20-standard/cluster.yml
  $0 remove examples/sno-4.20-standard/cluster.yml

This creates A records pointing to EXTERNAL_IP for:
  - api.<cluster>.<domain>
  - api-int.<cluster>.<domain>
  - *.apps.<cluster>.<domain>

For more information, see llm.txt "Phase 6.5: External Access Configuration"
EOF
}

# Main script logic
case "${1:-}" in
    add)
        if [ -z "$2" ]; then
            print_error "Usage: $0 add <cluster_config.yml>"
            exit 1
        fi
        add_dns_records "$2"
        ;;
    remove)
        if [ -z "$2" ]; then
            print_error "Usage: $0 remove <cluster_config.yml>"
            exit 1
        fi
        remove_dns_records "$2"
        ;;
    list)
        if [ -z "$2" ]; then
            print_error "Usage: $0 list <cluster_config.yml>"
            exit 1
        fi
        list_dns_records "$2"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Invalid command: ${1:-}"
        echo ""
        usage
        exit 1
        ;;
esac
