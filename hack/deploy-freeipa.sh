#!/bin/bash
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -xe

# Store the original directory
SCRIPT_DIR="$(pwd)"

# Function to prompt for value with default
prompt_with_default() {
    local prompt=$1
    local default=$2
    local value

    read -p "$prompt [$default]: " value
    echo ${value:-$default}
}

# Function to print status messages with color
print_status() {
    local message=$1
    local status=$2
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local NC='\033[0m'  # No Color

    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}✓ ${message}${NC}"
    else
        echo -e "${RED}✗ ${message}${NC}"
    fi
}

# Function to print info messages with color
print_info() {
    local message=$1
    local BLUE='\033[0;34m'
    local NC='\033[0m'  # No Color
    echo -e "${BLUE}ℹ ${message}${NC}"
}

if [ ! -d /opt/freeipa-workshop-deployer ]; then
  sudo mkdir -p /opt/freeipa-workshop-deployer
  sudo chown -R $USER:users /opt/freeipa-workshop-deployer
  cd /opt/
  sudo -u $USER git clone https://github.com/tosin2013/freeipa-workshop-deployer.git
  cd freeipa-workshop-deployer
else
  cd /opt/freeipa-workshop-deployer
  sudo chown -R $USER:users .
  git config pull.rebase false
  git pull
fi

cd /opt/freeipa-workshop-deployer
sudo cp "${SCRIPT_DIR}/hack/freeipa_vars.sh" vars.sh
sudo ./bootstrap.sh 

# Create basic all.yml if it doesn't exist
if [ ! -f all.yml ]; then
    print_info "Creating all.yml..."
    print_info "Please provide the following information:"
    
    # Prompt for all.yml values
    DNS_FORWARDER=$(prompt_with_default "Enter DNS forwarder" "1.1.1.1")
    DOMAIN=$(prompt_with_default "Enter domain name" "example.com")
    ADMIN_USER="cloud-user"
    
    cat > all.yml <<EOL
---
dns_forwarder: "${DNS_FORWARDER}"
domain: "${DOMAIN}"
admin_user: "${ADMIN_USER}"
EOL
    print_status "all.yml created" 0
else
    print_status "all.yml already exists" 0
    print_info "To recreate all.yml, delete the existing file and run bootstrap.sh again"
fi

# Ensure proper permissions for all files
sudo chown -R $USER:users ./vars.sh ./all.yml 2>/dev/null || true
cat vars.sh
sudo bash -x  ./total_deployer.sh kcli
