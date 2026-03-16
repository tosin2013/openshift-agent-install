#!/usr/bin/env python3
import yaml
import base64
import sys
from pathlib import Path

def base64_encode(s: str) -> str:
    return base64.b64encode(s.encode()).decode()

def generate_bmc_hosts(nodes_file: Path, output_file: Path):
    # Read the nodes yaml file
    with open(nodes_file) as f:
        data = yaml.safe_load(f)
    
    # Store all resources
    resources = []

    infra_env = "openshift" # Default namespace/infraenv name

    for node in data['nodes']:
        # Extract values
        hostname = node['hostname']
        bmc = node['bmc']
        mac = node['interfaces'][0]['mac_address'] # Use first interface's MAC
        
        # Create unique names
        secret_name = f"bmc-{hostname}-credentials"
        bmh_name = f"bmh-{hostname}"

        # Create Secret resource
        secret = {
            "apiVersion": "v1",
            "data": {
                "username": base64_encode(bmc['username']),
                "password": base64_encode(bmc['password'])
            },
            "kind": "Secret",
            "metadata": {
                "name": secret_name,
                "namespace": infra_env
            },
            "type": "Opaque"
        }
        resources.append(secret)

        # Create BareMetalHost resource
        bmh = {
            "apiVersion": "metal3.io/v1alpha1",
            "kind": "BareMetalHost",
            "metadata": {
                "annotations": {
                    "bmac.agent-install.openshift.io/hostname": hostname,
                    "inspect.metal3.io": "disabled"
                },
                "labels": {
                    "infraenvs.agent-install.openshift.io": infra_env
                },
                "name": bmh_name,
                "namespace": infra_env
            },
            "spec": {
                "automatedCleaningMode": "disabled",
                "bmc": {
                    "address": bmc['address'],
                    "credentialsName": secret_name,
                    "disableCertificateVerification": True
                },
                "bootMACAddress": mac.lower(),
                "online": False
            }
        }
        resources.append(bmh)

    # Write all resources to the output file
    with open(output_file, 'w') as f:
        yaml.safe_dump_all(resources, f, default_flow_style=False)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: generate_bmc_hosts.py <nodes_yaml> <output_yaml>")
        sys.exit(1)
    
    nodes_file = Path(sys.argv[1])
    output_file = Path(sys.argv[2])
    
    if not nodes_file.exists():
        print(f"Error: {nodes_file} not found")
        sys.exit(1)
        
    generate_bmc_hosts(nodes_file, output_file)
    print(f"Generated BMC hosts configuration in {output_file}")
