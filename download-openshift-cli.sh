#!/bin/bash

# OpenShift CLI Download Script
# Supports explicit version argument or auto-detection (RHEL/Ubuntu)
# Usage: ./download-openshift-cli.sh [version]
#   version: Optional - specific version like "4.20", "4.21", or "stable-4.20"
#   If not provided, auto-detects based on OS

set -e

# Accept optional version argument
REQUESTED_VERSION="${1:-}"

mkdir -p ./bin
cd ./bin

# Determine OC version to download
if [ -n "$REQUESTED_VERSION" ]; then
    # Explicit version provided
    if [[ "$REQUESTED_VERSION" =~ ^stable- ]]; then
        # Already in "stable-X.Y" format
        oc_version="$REQUESTED_VERSION"
    elif [[ "$REQUESTED_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
        # Version number like "4.20" -> "stable-4.20"
        oc_version="stable-$REQUESTED_VERSION"
    else
        echo "Error: Invalid version format '$REQUESTED_VERSION'. Use '4.20' or 'stable-4.20'"
        exit 1
    fi
    echo "Downloading OpenShift CLI version: $oc_version (explicitly requested)"
else
    # Auto-detect based on OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
    else
        OS_ID="unknown"
    fi

    case "$OS_ID" in
        rhel|centos|rocky|almalinux)
            # RHEL-based: detect version
            rhel_version=$(rpm -E %{rhel} 2>/dev/null || echo "9")
            if [ "$rhel_version" -eq 8 ]; then
                oc_version="stable-4.15"
            else
                oc_version="stable-4.17"
            fi
            echo "Detected RHEL-based OS (version $rhel_version), using $oc_version"
            ;;
        ubuntu|debian)
            # Ubuntu/Debian: default to latest stable
            oc_version="stable-4.21"
            echo "Detected Ubuntu/Debian, using $oc_version"
            ;;
        *)
            # Unknown OS: default to latest stable
            oc_version="stable-4.21"
            echo "Unknown OS ($OS_ID), defaulting to $oc_version"
            ;;
    esac
fi

# Download and extract OpenShift CLI
echo "Downloading OpenShift CLI from: https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$oc_version/"
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$oc_version/openshift-client-linux.tar.gz
tar zxvf openshift-client-linux.tar.gz
rm -f openshift-client-linux.tar.gz

# Download and extract OpenShift Installer
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$oc_version/openshift-install-linux.tar.gz
tar zxvf openshift-install-linux.tar.gz
rm -f openshift-install-linux.tar.gz

rm -f README.md

chmod a+x oc
chmod a+x kubectl
chmod a+x openshift-install

echo "✓ OpenShift CLI tools installed successfully"
./oc version --client
