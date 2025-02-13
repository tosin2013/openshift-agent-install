#!/bin/bash

# This script validates the environment for end-to-end tests targeting OpenShift 4.17

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print with color
print_status() {
    if [ $2 -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        exit 1 # Exit on failure to prevent further execution
    fi
}

print_section() {
    echo -e "\n${YELLOW}$1${NC}"
    echo "================================"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

# Check if oc is installed
print_section "Checking oc installation"
if command_exists oc; then
    print_status "oc is installed" 0
else
    print_status "oc is not installed" 1
fi

# Check oc version (replace with actual version check if needed)
print_section "Checking oc version"
oc version &> /dev/null # Suppress output for now. Replace with actual version check if needed.
print_status "oc version check passed (placeholder)" $? # Placeholder. Replace with actual version check.

# Check if pull secret exists
print_section "Checking for pull secret"
if [ -f "/home/lab-user/pullsecret.json" ]; then
    print_status "Pull secret found" 0
else
    print_status "Pull secret not found at /home/lab-user/pullsecret.json" 1
fi

# Check if connected to OpenShift cluster (replace with actual cluster check)
print_section "Checking OpenShift cluster connection"
oc cluster-info &> /dev/null # Suppress output for now. Replace with actual cluster check.
print_section "Checking Operating System"
if [[ "$(/usr/bin/lsb_release -d)" == *"Red Hat Enterprise Linux release 9.5 (Plow)"* ]]; then
    print_status "Operating System is Red Hat Enterprise Linux release 9.5 (Plow)" 0
else
    print_status "Operating System is not Red Hat Enterprise Linux release 9.5 (Plow)" 1
fi

# Check if connected to OpenShift cluster (replace with actual cluster check)
print_section "Checking OpenShift cluster connection"
oc cluster-info &> /dev/null # Suppress output for now. Replace with actual cluster check.
print_status "Connected to OpenShift cluster (placeholder)" $? # Placeholder. Replace with actual cluster check.
