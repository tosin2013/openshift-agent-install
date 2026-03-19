#!/bin/bash
# configure-letsencrypt-certs.sh - Obtain and install Let's Encrypt certificates for OpenShift
# This script uses certbot with Route53 DNS-01 validation to obtain trusted TLS certificates

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

# Script configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LETSENCRYPT_DIR="/etc/letsencrypt"
CERT_STAGING="${CERT_STAGING:-false}"

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"

    # Detect container runtime
    if command -v podman &>/dev/null; then
        CONTAINER_RUNTIME="podman"
        print_status "Container runtime: podman" 0
    elif command -v docker &>/dev/null; then
        CONTAINER_RUNTIME="docker"
        print_status "Container runtime: docker" 0
    else
        print_error "Neither podman nor docker found"
        echo "Please install podman or docker"
        exit 1
    fi

    # Check for oc CLI
    if ! command -v oc &>/dev/null; then
        print_error "oc CLI not found"
        echo "Please ensure OpenShift CLI is installed"
        echo "Run: ./download-openshift-cli.sh"
        exit 1
    fi
    print_status "OpenShift CLI is installed" 0

    # Check AWS credentials
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        print_error "AWS credentials not set"
        echo ""
        echo "Please set AWS credentials for Route53 DNS validation:"
        echo "  export AWS_ACCESS_KEY_ID=\"your-key-id\""
        echo "  export AWS_SECRET_ACCESS_KEY=\"your-secret-key\""
        exit 1
    fi
    print_status "AWS credentials configured" 0

    # Check for EMAIL variable
    if [ -z "$EMAIL" ]; then
        print_error "EMAIL environment variable not set"
        echo ""
        echo "Please set an email address for Let's Encrypt notifications:"
        echo "  export EMAIL=\"admin@example.com\""
        exit 1
    fi
    print_status "Email configured: ${EMAIL}" 0

    # Check if letsencrypt directory exists, create if not
    if [ ! -d "$LETSENCRYPT_DIR" ]; then
        print_info "Creating ${LETSENCRYPT_DIR} directory..."
        sudo mkdir -p "$LETSENCRYPT_DIR"
    fi
    print_status "Let's Encrypt directory ready" 0
}

# Function to validate cluster access
validate_cluster_access() {
    print_section "Validating Cluster Access"

    # Check if KUBECONFIG is set
    if [ -z "$KUBECONFIG" ]; then
        print_error "KUBECONFIG environment variable not set"
        echo ""
        echo "Please set KUBECONFIG to your cluster's kubeconfig file:"
        echo "  export KUBECONFIG=~/generated_assets/<cluster-name>/auth/kubeconfig"
        exit 1
    fi

    print_info "Using KUBECONFIG: ${KUBECONFIG}"

    # Test cluster connectivity
    if ! oc whoami &>/dev/null; then
        print_error "Cannot connect to cluster"
        echo "Please ensure:"
        echo "  1. KUBECONFIG is set correctly"
        echo "  2. Cluster is accessible"
        echo "  3. You are logged in"
        exit 1
    fi

    CURRENT_USER=$(oc whoami)
    print_status "Connected to cluster as: ${CURRENT_USER}" 0

    # Verify we can access nodes
    if ! oc get nodes &>/dev/null; then
        print_error "Cannot access cluster nodes"
        exit 1
    fi
    print_status "Cluster access validated" 0
}

# Function to extract cluster information
extract_cluster_info() {
    print_section "Extracting Cluster Information"

    # Get API endpoint
    API_ENDPOINT=$(oc whoami --show-server 2>/dev/null | sed 's|https://||' | sed 's|:6443||')
    if [ -z "$API_ENDPOINT" ]; then
        print_error "Failed to extract API endpoint"
        exit 1
    fi
    print_info "API Endpoint: ${API_ENDPOINT}"

    # Extract cluster name and base domain from API endpoint
    # Format is typically: api.<cluster>.<domain>
    CLUSTER_NAME=$(echo "$API_ENDPOINT" | cut -d'.' -f2)
    BASE_DOMAIN=$(echo "$API_ENDPOINT" | cut -d'.' -f3-)

    if [ -z "$CLUSTER_NAME" ] || [ -z "$BASE_DOMAIN" ]; then
        print_error "Failed to parse cluster name and base domain from API endpoint"
        echo "API Endpoint: ${API_ENDPOINT}"
        exit 1
    fi

    print_info "Cluster Name: ${CLUSTER_NAME}"
    print_info "Base Domain: ${BASE_DOMAIN}"

    # Get wildcard apps domain
    APPS_DOMAIN=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}' 2>/dev/null)
    if [ -z "$APPS_DOMAIN" ]; then
        APPS_DOMAIN="apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
        print_info "Using default apps domain: ${APPS_DOMAIN}"
    else
        print_info "Apps Domain: ${APPS_DOMAIN}"
    fi

    print_status "Cluster information extracted" 0
}

# Function to backup existing certificates
backup_existing_certificates() {
    print_section "Backing Up Existing Certificates"

    # Check if router-certs secret exists
    if oc get secret router-certs -n openshift-ingress &>/dev/null; then
        print_info "Found existing router-certs secret, backing up..."

        BACKUP_DIR="${HOME}/generated_assets/${CLUSTER_NAME}/cert-backups"
        mkdir -p "$BACKUP_DIR"

        BACKUP_FILE="${BACKUP_DIR}/router-certs-backup-$(date +%Y%m%d-%H%M%S).yaml"
        oc get secret router-certs -n openshift-ingress -o yaml > "$BACKUP_FILE"

        print_status "Backup saved to: ${BACKUP_FILE}" 0
    else
        print_info "No existing router-certs secret found (first-time setup)"
        print_status "No backup needed" 0
    fi
}

# Function to obtain Let's Encrypt certificates
obtain_certificates() {
    print_section "Obtaining Let's Encrypt Certificates"

    # Determine certbot server (staging or production)
    if [ "$CERT_STAGING" == "true" ]; then
        CERTBOT_SERVER="--staging"
        print_info "Using Let's Encrypt STAGING environment (for testing)"
    else
        CERTBOT_SERVER=""
        print_info "Using Let's Encrypt PRODUCTION environment"
    fi

    # Build certbot command
    print_info "Running certbot with Route53 DNS-01 validation..."
    print_info "Domains:"
    print_info "  - api.${CLUSTER_NAME}.${BASE_DOMAIN}"
    print_info "  - *.${APPS_DOMAIN}"

    # Run certbot in container
    sudo ${CONTAINER_RUNTIME} run -it --rm \
        -v "${LETSENCRYPT_DIR}:/etc/letsencrypt:Z" \
        -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
        -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
        certbot/dns-route53 certonly \
            --dns-route53 \
            --non-interactive \
            --agree-tos \
            ${CERTBOT_SERVER} \
            --email "${EMAIL}" \
            -d "api.${CLUSTER_NAME}.${BASE_DOMAIN}" \
            -d "*.${APPS_DOMAIN}" \
            || {
                print_error "Certbot failed to obtain certificates"
                echo ""
                echo "Common issues:"
                echo "  1. DNS records not propagated (wait a few minutes)"
                echo "  2. AWS credentials don't have Route53 permissions"
                echo "  3. Route53 hosted zone doesn't exist for ${BASE_DOMAIN}"
                echo ""
                echo "For testing, use staging environment:"
                echo "  export CERT_STAGING=true"
                exit 1
            }

    print_status "Certificates obtained successfully" 0

    # Display certificate location
    CERT_DIR="${LETSENCRYPT_DIR}/live/api.${CLUSTER_NAME}.${BASE_DOMAIN}"
    print_info "Certificate files:"
    print_info "  ${CERT_DIR}/fullchain.pem"
    print_info "  ${CERT_DIR}/privkey.pem"
}

# Function to install certificates to cluster
install_certificates_to_cluster() {
    print_section "Installing Certificates to Cluster"

    CERT_DIR="${LETSENCRYPT_DIR}/live/api.${CLUSTER_NAME}.${BASE_DOMAIN}"

    # Verify certificate files exist
    if [ ! -f "${CERT_DIR}/fullchain.pem" ] || [ ! -f "${CERT_DIR}/privkey.pem" ]; then
        print_error "Certificate files not found in ${CERT_DIR}"
        exit 1
    fi

    # Delete existing secret if it exists
    if oc get secret router-certs -n openshift-ingress &>/dev/null; then
        print_info "Deleting existing router-certs secret..."
        oc delete secret router-certs -n openshift-ingress
    fi

    # Create new secret with Let's Encrypt certificates
    print_info "Creating router-certs secret..."
    sudo oc create secret tls router-certs \
        --cert="${CERT_DIR}/fullchain.pem" \
        --key="${CERT_DIR}/privkey.pem" \
        -n openshift-ingress \
        || {
            print_error "Failed to create router-certs secret"
            exit 1
        }

    print_status "Secret created successfully" 0

    # Patch IngressController to use the new certificate
    print_info "Patching IngressController to use Let's Encrypt certificates..."
    oc patch ingresscontroller default \
        -n openshift-ingress-operator \
        --type=merge \
        --patch='{"spec":{"defaultCertificate":{"name":"router-certs"}}}' \
        || {
            print_error "Failed to patch IngressController"
            exit 1
        }

    print_status "IngressController patched successfully" 0
}

# Function to verify certificate installation
verify_certificate_installation() {
    print_section "Verifying Certificate Installation"

    # Check secret exists
    if oc get secret router-certs -n openshift-ingress &>/dev/null; then
        print_status "router-certs secret exists" 0
    else
        print_error "router-certs secret not found"
        exit 1
    fi

    # Check IngressController is patched
    DEFAULT_CERT=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate.name}' 2>/dev/null)
    if [ "$DEFAULT_CERT" == "router-certs" ]; then
        print_status "IngressController configured to use router-certs" 0
    else
        print_error "IngressController not configured correctly"
        echo "Current defaultCertificate: ${DEFAULT_CERT}"
        exit 1
    fi

    print_info "Waiting for router pods to restart with new certificates..."
    print_info "This may take 1-2 minutes..."

    # Wait for router deployment to rollout
    sleep 10
    oc rollout status deployment/router-default -n openshift-ingress --timeout=5m || true

    print_status "Certificate installation verified" 0
}

# Function to display certificate information
display_certificate_info() {
    print_section "Certificate Installation Complete"

    CERT_DIR="${LETSENCRYPT_DIR}/live/api.${CLUSTER_NAME}.${BASE_DOMAIN}"

    echo ""
    echo -e "${GREEN}Let's Encrypt certificates successfully installed!${NC}"
    echo ""
    echo "Certificate details:"
    sudo ${CONTAINER_RUNTIME} run --rm \
        -v "${LETSENCRYPT_DIR}:/etc/letsencrypt:Z" \
        certbot/dns-route53 certificates | grep -A 10 "api.${CLUSTER_NAME}.${BASE_DOMAIN}" || true
    echo ""
    echo "Next steps:"
    echo "  1. Access the cluster console with HTTPS:"
    echo "     https://console-openshift-console.${APPS_DOMAIN}/"
    echo ""
    echo "  2. Verify certificate in browser (should show Let's Encrypt)"
    echo ""
    echo "  3. Test certificate with curl:"
    echo "     curl -I https://console-openshift-console.${APPS_DOMAIN}/"
    echo ""
    echo "Certificate renewal:"
    echo "  Certificates expire in 90 days. To renew:"
    echo "  sudo ${CONTAINER_RUNTIME} run --rm \\"
    echo "    -v \"${LETSENCRYPT_DIR}:/etc/letsencrypt:Z\" \\"
    echo "    -e AWS_ACCESS_KEY_ID=\"\${AWS_ACCESS_KEY_ID}\" \\"
    echo "    -e AWS_SECRET_ACCESS_KEY=\"\${AWS_SECRET_ACCESS_KEY}\" \\"
    echo "    certbot/dns-route53 renew"
    echo ""
    echo "  Then re-run this script to install renewed certificates"
}

# Usage function
usage() {
    cat << EOF
Usage: $0

Obtain and install Let's Encrypt certificates for OpenShift using Route53 DNS-01 validation.

Prerequisites:
  - oc CLI installed and cluster accessible
  - AWS credentials with Route53 permissions
  - EMAIL environment variable set
  - KUBECONFIG set to cluster kubeconfig
  - Route53 DNS records already configured
  - Podman or Docker installed

Required Environment Variables:
  AWS_ACCESS_KEY_ID       - AWS access key for Route53
  AWS_SECRET_ACCESS_KEY   - AWS secret key for Route53
  EMAIL                   - Email for Let's Encrypt notifications
  KUBECONFIG              - Path to cluster kubeconfig file

Optional Environment Variables:
  CERT_STAGING            - Use Let's Encrypt staging (default: false)

Example:
  export AWS_ACCESS_KEY_ID="your-key-id"
  export AWS_SECRET_ACCESS_KEY="your-secret-key"
  export EMAIL="admin@example.com"
  export KUBECONFIG=~/generated_assets/sno-4-20/auth/kubeconfig

  # For testing (staging environment)
  export CERT_STAGING=true

  $0

This will:
  1. Obtain Let's Encrypt certificates via Route53 DNS-01 validation
  2. Backup existing certificates (if any)
  3. Create router-certs secret in openshift-ingress namespace
  4. Patch IngressController to use the new certificates
  5. Verify certificate installation

For more information, see llm.txt "Phase 6.5: External Access Configuration"
EOF
}

# Main script execution
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    # Execute workflow
    check_prerequisites
    validate_cluster_access
    extract_cluster_info
    backup_existing_certificates
    obtain_certificates
    install_certificates_to_cluster
    verify_certificate_installation
    display_certificate_info

    echo -e "\n${GREEN}Certificate configuration complete!${NC}"
}

# Run main function
main "$@"
