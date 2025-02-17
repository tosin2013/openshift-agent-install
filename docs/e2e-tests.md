# End-to-End Tests Documentation

This document provides an overview of the end-to-end (e2e) tests and describes how to run them, along with the purpose, inputs, and outputs of each script involved in the testing process.

## Quick Start

### Prerequisites
- Red Hat Enterprise Linux 9.5 (Plow)
- Sudo privileges
- Pull secret file at `/home/lab-user/pullsecret.json`
- Sufficient disk space for VM creation
- Minimum 32GB RAM recommended for testing

### Steps

1. First, bootstrap the environment. You'll need to specify a site configuration to use:
```bash
# First, select a configuration to use (example or custom)
export SITE_CONFIG_DIR=examples  # or site-config for custom configs
export SITE_CONFIG=sno-bond0-signal-vlan  # or your custom config name

# Set required environment variables
export ANSIBLE_ALL_VARIABLES="${SITE_CONFIG_DIR}/${SITE_CONFIG}/cluster.yml"

# Run the bootstrap script
# This will install required packages, configure SELinux, setup virtualization, etc.
sudo -E ./e2e-tests/bootstrap_env.sh
```

The `-E` flag with sudo preserves the environment variables we set. The script needs these variables to:
- Configure the VyOS router with proper domain information
- Set up virtual networks correctly
- Configure DNS settings

2. Run the e2e tests with a specific configuration. You can use either:
   - Example configurations from the `examples/` directory
   - Custom configurations from your `site-config/` directory

```bash
# Using the default examples directory
./e2e-tests/run_e2e.sh sno-bond0-signal-vlan

# Or using a custom site config directory
SITE_CONFIG_DIR=site-config ./e2e-tests/run_e2e.sh raza-sno.lab.kemo.network

# Optionally specify a custom path for generated assets
GENERATED_ASSET_PATH=/path/to/assets ./e2e-tests/run_e2e.sh sno-bond0-signal-vlan
```

3. To cleanup after testing:
```bash
# Clean up the test environment including:
# - VyOS router
# - Test VMs
# - Generated assets
# - Virtual networks
./e2e-tests/delete_e2e.sh sno-bond0-signal-vlan

# If using custom site config:
SITE_CONFIG_DIR=site-config ./e2e-tests/delete_e2e.sh raza-sno.lab.kemo.network
```


## Overview

The end-to-end tests are designed to validate the functionality of the OpenShift Agent Installer. These tests automate the deployment and configuration of OpenShift clusters in a virtualized environment. The tests cover various aspects of the installation process, including environment setup, ISO creation, VM deployment, and cluster validation.

These tests are designed to run on Red Hat Enterprise Linux release 9.5 (Plow).

## Scripts

The e2e tests consist of the following scripts:

*   `bootstrap_env.sh`: This script sets up the environment for the e2e tests.
*   `run_e2e.sh`: This script runs the end-to-end tests.
*   `validate_env.sh`: This script validates the environment for the end-to-end tests.
*   `delete_e2e.sh`: This script cleans up the test environment.

### `delete_e2e.sh`

#### Purpose

The `delete_e2e.sh` script performs a comprehensive cleanup of the test environment, including:
- Removing the VyOS router
- Destroying and undefining test VMs
- Cleaning up virtual disk images
- Removing generated assets
- Destroying virtual networks

#### Inputs

This script takes the following inputs:

*   `SITE_CONFIG_DIR`: The directory containing the cluster configuration files. Defaults to `examples`.
*   A site config folder name as the first argument, matching the one used with `run_e2e.sh`.

#### Outputs

This script cleans up all resources created during the e2e tests, including:
- All test VMs and their associated disk images
- The agent ISO image
- Generated assets in `$HOME/generated_assets/<cluster_name>`
- Virtual networks (1924-1928)
- VyOS router and its configuration

### `bootstrap_env.sh`

#### Purpose

The `bootstrap_env.sh` script sets up the environment for the e2e tests. It installs system packages, configures SELinux, installs container tools, configures virtual networks, sets up the VyOS router, sets up virtualization, sets up registry authentication, handles SELinux policies, and validates the installation.

#### Inputs

This script requires the following environment variables:

*   `ANSIBLE_ALL_VARIABLES`: Path to the cluster.yml configuration file (e.g., "${SITE_CONFIG_DIR}/${SITE_CONFIG}/cluster.yml"). Required for VyOS router configuration and network setup.
*   `SUDO_USER`: The user to configure registry authentication for.
*   `OPENWEATHER_API_KEY`: The API key for the OpenWeather API.

Additional requirements:
*   A pull secret must be present at `/home/lab-user/pullsecret.json`
*   Must be run with sudo and the -E flag to preserve environment variables (e.g., `sudo -E ./e2e-tests/bootstrap_env.sh`)

#### Outputs

This script sets up the environment for the e2e tests. It does not produce any direct outputs, but it ensures that the environment is properly configured for the tests to run.

### `run_e2e.sh`

#### Purpose

The `run_e2e.sh` script runs the end-to-end tests. It creates a test ISO, deploys test VMs, monitors the test VMs, executes the tests, and cleans up the test environment.

#### Inputs

This script takes the following inputs:

*   `SITE_CONFIG_DIR`: The directory containing the cluster configuration files. Defaults to `examples`.
*   `GENERATED_ASSET_PATH`: The directory to store generated assets. Defaults to `$HOME/generated_assets`.
*   A site config folder name as the first argument. This folder should exist under the `SITE_CONFIG_DIR` and contain `cluster.yml` and `nodes.yml` files.

It also relies on the following environment variables:

*   `CLUSTER_NAME`: The name of the cluster.
*   The `nodes.yml` file path as the first argument to the `deploy_test_vms`, `monitor_test_vms`, and `cleanup_test_env` functions.

#### Outputs

This script runs the end-to-end tests. It does not produce any direct outputs, but it validates the functionality of the OpenShift Agent Installer.

### `validate_env.sh`

#### Purpose

The `validate_env.sh` script validates the environment for the end-to-end tests. It checks if `oc` is installed, checks the `oc` version, checks if the pull secret exists, and checks if it is connected to an OpenShift cluster.

#### Inputs

This script does not take any direct inputs from the user.

#### Outputs

This script validates the environment for the e2e tests. It does not produce any direct outputs, but it ensures that the environment is properly configured for the tests to run.
