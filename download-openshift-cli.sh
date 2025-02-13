#!/bin/bash

mkdir -p ./bin
cd ./bin

# Determine the RHEL version
rhel_version=$(rpm -E %{rhel})

if [ "$rhel_version" -eq 8 ]; then
    oc_version="stable-4.15"
else
    oc_version="stable-4.17"
fi

# Download and extract OpenShift CLI
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$oc_version/openshift-client-linux.tar.gz
tar zxvf openshift-client-linux.tar.gz
rm -f openshift-client-linux.tar.gz

# Download and extract OpenShift Installer
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$oc_version/openshift-install-linux.tar.gz
tar zxvf openshift-install-linux.tar.gz
rm -f openshift-install-linux.tar.gz

rm README.md

chmod a+x oc
chmod a+x kubectl
chmod a+x openshift-install
