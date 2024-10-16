#!/bin/bash

# Exit on error
set -e

# Where are we pulling cluster configuration from - make a `clusters` directory and store your config there, it's in .gitignore
SITE_CONFIG_DIR="${SITE_CONFIG_DIR:-examples}"
#SITE_CONFIG_DIR="clusters"

# Check if GENERATED_ASSET_PATH is set, if not, use the home directory
if [ -z "${GENERATED_ASSET_PATH}" ]; then
    GENERATED_ASSET_PATH="${HOME}/generated_assets"
fi

# Check to see if the generated asset path exists
if [ ! -d "${GENERATED_ASSET_PATH}" ]; then
    mkdir -p "${GENERATED_ASSET_PATH}"
fi

echo "Generated asset path is: ${GENERATED_ASSET_PATH}"

# Check to see if there was an argument passed for the cluster config
if [ -z "$1" ]; then
    echo "No site config folder specified"
    exit 1
fi

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Download the binaries
if [ ! -d "bin" ] || [ ! -f "bin/openshift-install" ] || [ ! -f "bin/oc" ]; then
    ./download-openshift-cli.sh
fi

cd $SCRIPT_DIR/..

# Check that the cluster name exists
if [ ! -d "${SITE_CONFIG_DIR}/$1" ]; then
    echo "No site config folder found for $1"
    echo "Found these site config folders:"
    ls -1 ${SITE_CONFIG_DIR}
    exit 1
fi

# Get the cluster_name
CLUSTER_NAME=$(grep "cluster_name" ${SITE_CONFIG_DIR}/${1}/cluster.yml | awk '{print $2}' | tr -d '"')
# Get the base_domain
BASE_DOMAIN=$(grep "base_domain" ${SITE_CONFIG_DIR}/${1}/cluster.yml | awk '{print $2}' | tr -d '"')

# Display header
echo "============================================================="
echo "Creating Agent Based Installer ISO for cluster:"
echo " ${CLUSTER_NAME}"
echo "============================================================="
echo -e "\n - Templating the manifests for the cluster..."

# Run the templating playbook
ansible-playbook -e "@${SITE_CONFIG_DIR}/${1}/cluster.yml" -e "@${SITE_CONFIG_DIR}/${1}/nodes.yml" -e "generated_asset_path=${GENERATED_ASSET_PATH}" playbooks/create-manifests.yml ${DEBUG} || { echo "Failed to template manifests"; exit 1; }

# Generate the ABI ISO
echo "============================================================="
echo -e "\nGenerating Install ISO...\n"
ls -lath ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/  || { echo "Failed to list directory"; exit 1; }
./bin/openshift-install agent create image --dir ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/  || { echo "Failed to generate ISO"; exit 1; }

# Display footer
echo -e "\nISO created successfully!"
echo "Location: ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/agent.x86_64.iso"
echo "============================================================="
echo "Next steps:"
echo "  1. Copy the ISO to a location accessible by the baremetal/virtual hosts"
echo "  2. Attach and boot the hosts from the ISO"
echo "  3. Watch the installation process with:"
echo "     ./bin/openshift-install agent wait-for bootstrap-complete --dir ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/"
echo "     ./bin/openshift-install agent wait-for install-complete --dir ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/"
echo "  4. Access the cluster from the Web GUI with:"
echo "     kubeadmin / $(cat ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/auth/kubeadmin-password)"
echo "     https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}/"
echo "  5. Access the cluster with via the CLI with:"
echo "     oc --kubeconfig ${GENERATED_ASSET_PATH}/${CLUSTER_NAME}/auth/kubeconfig get co"
echo "============================================================="
