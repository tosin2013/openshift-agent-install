#!/bin/bash 

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -f ${SCRIPT_DIR}/../hack/freeipa_vars.sh ]; then
  source ${SCRIPT_DIR}/../hack/freeipa_vars.sh
else 
  exit 1
fi

# Set CLUSTER_FILE_PATH based on the provided site_config
if [ ! -z "$1" ]; then
    CLUSTER_FILE_PATH="${SCRIPT_DIR}/../examples/${1}/cluster.yml"
else
    echo "Error: No site config folder specified"
    exit 1
fi

# Verify the cluster.yml file exists
if [ ! -f "$CLUSTER_FILE_PATH" ]; then
    echo "Error: cluster.yml not found at $CLUSTER_FILE_PATH"
    exit 1
fi

function create_dns_entries(){
    API_ENDPOINT=$(yq eval '.api_vips' "$CLUSTER_FILE_PATH" | sed 's/^- //')
    CLUSTER_NAME=$(yq eval '.cluster_name' "$CLUSTER_FILE_PATH")
    APPS_ENDPOINT=$(yq eval '.app_vips' "$CLUSTER_FILE_PATH" | sed 's/^- //')

    DOMAIN_NAME=api.${CLUSTER_NAME}.${DOMAIN}

    echo "API_ENDPOINT: $API_ENDPOINT"
    echo "CLUSTER_NAME: $CLUSTER_NAME"
    echo "APPS_ENDPOINT: $APPS_ENDPOINT"
    echo "DOMAIN_NAME: $DOMAIN_NAME"

    # Update the DNS using the add_ipa_entry.yaml playbook
    # Check if add_ipa_entry.yaml exists
    if [ ! -f "$SCRIPT_DIR/../playbooks/ipaserver-helpers/add_ipa_entry.yaml" ]; then
        echo "add_ipa_entry.yaml not found. Exiting..."
        exit 1
    fi

    ansible-playbook "$SCRIPT_DIR/../playbooks/ipaserver-helpers/add_ipa_entry.yaml" \
      --extra-vars "freeipa_server_admin_password=${FREEIPA_ADMIN_PASSWORD}" \
      --extra-vars "key=api.${CLUSTER_NAME}" \
      --extra-vars "freeipa_server_fqdn=idm.${DOMAIN}" \
      --extra-vars "value=${API_ENDPOINT}" \
      --extra-vars "freeipa_server_domain=${DOMAIN}" --extra-vars "action=present" -vvv || exit $?

    DOMAIN_NAME=*.apps.${CLUSTER_NAME}.${DOMAIN}
    ansible-playbook $SCRIPT_DIR/../playbooks/ipaserver-helpers/add_ipa_entry.yaml \
      --extra-vars "freeipa_server_admin_password=${FREEIPA_ADMIN_PASSWORD}" \
      --extra-vars "key=*.apps.${CLUSTER_NAME}" \
      --extra-vars "freeipa_server_fqdn=idm.${DOMAIN}" \
      --extra-vars "value=${APPS_ENDPOINT}" \
      --extra-vars "freeipa_server_domain=${DOMAIN}" --extra-vars "action=present" -vvv || exit $?

      export vm_name="freeipa"
      export ip_address=$(sudo kcli info vm "$vm_name" "$vm_name" | grep ip: | awk '{print $2}' | head -1)
      export interface_name="bond0" # "System eth0"
      echo "VM $vm_name created with IP address $ip_address"

      # Remove old DNS entries
      sudo nmcli connection modify "${interface_name}" ipv4.dns ""

      # Add new DNS entries
      sudo nmcli connection modify "${interface_name}" ipv4.dns $ip_address,147.75.207.207
      sudo nmcli connection reload

      # List the DNS information using nmcli
      sudo nmcli connection show "${interface_name}" | grep ipv4.dns
      sudo systemctl restart NetworkManager
}

create_dns_entries
