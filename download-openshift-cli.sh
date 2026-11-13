#!/bin/bash

# OpenShift CLI Download Script
# Downloads the latest OpenShift CLI and installer by default.
# Pass a version argument to install a specific release.
#
# Usage:
#   ./download-openshift-cli.sh          # Downloads latest stable
#   ./download-openshift-cli.sh 4.22     # Downloads stable-4.22
#   ./download-openshift-cli.sh 5.0      # Downloads stable-5.0 (uses openshift-v5 mirror)
#   ./download-openshift-cli.sh latest   # Explicitly downloads latest

set -e

REQUESTED_VERSION="${1:-latest}"

mkdir -p ./bin
cd ./bin

if [ "$REQUESTED_VERSION" = "latest" ]; then
    oc_version="latest"
elif [[ "$REQUESTED_VERSION" =~ ^stable- ]]; then
    oc_version="$REQUESTED_VERSION"
elif [[ "$REQUESTED_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    oc_version="stable-$REQUESTED_VERSION"
else
    echo "Error: Invalid version format '$REQUESTED_VERSION'"
    echo "Usage: $0 [version]"
    echo "  version: '4.21', '4.22', '5.0', '5.1', 'stable-4.22', or 'latest' (default)"
    exit 1
fi

# Select mirror based on major version (OCP 5+ uses openshift-v5 mirror path)
OCP_MAJOR=$(echo "$oc_version" | sed 's/^stable-//' | cut -d'.' -f1)
if [ "$oc_version" != "latest" ] && [ "$OCP_MAJOR" -ge 5 ] 2>/dev/null; then
    MIRROR_MAJOR="openshift-v5"
else
    MIRROR_MAJOR="openshift-v4"
fi
BASE_URL="https://mirror.openshift.com/pub/${MIRROR_MAJOR}/x86_64/clients/ocp/$oc_version"

echo "Downloading OpenShift CLI ($oc_version) from: $BASE_URL/"

wget -q --show-progress "$BASE_URL/openshift-client-linux.tar.gz"
tar zxf openshift-client-linux.tar.gz
rm -f openshift-client-linux.tar.gz

wget -q --show-progress "$BASE_URL/openshift-install-linux.tar.gz"
tar zxf openshift-install-linux.tar.gz
rm -f openshift-install-linux.tar.gz

rm -f README.md

chmod a+x oc kubectl openshift-install

echo ""
echo "OpenShift CLI tools installed to ./bin/"
./oc version --client
./openshift-install version | head -1
