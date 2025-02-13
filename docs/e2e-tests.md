# End-to-End Tests Documentation

This document provides an overview of the end-to-end (e2e) tests and describes the purpose, inputs, and outputs of each script involved in the testing process.

## Overview

The end-to-end tests are designed to validate the functionality of the OpenShift Agent Installer. These tests automate the deployment and configuration of OpenShift clusters in a virtualized environment. The tests cover various aspects of the installation process, including environment setup, ISO creation, VM deployment, and cluster validation.

These tests are designed to run on Red Hat Enterprise Linux release 9.5 (Plow).

## Scripts

The e2e tests consist of the following scripts:

*   `bootstrap_env.sh`: This script sets up the environment for the e2e tests.
*   `run_e2e.sh`: This script runs the end-to-end tests.
*   `validate_env.sh`: This script validates the environment for the end-to-end tests.

### `bootstrap_env.sh`

#### Purpose

The `bootstrap_env.sh` script sets up the environment for the e2e tests. It installs system packages, configures SELinux, installs container tools, configures virtual networks, sets up the VyOS router, sets up virtualization, sets up registry authentication, handles SELinux policies, and validates the installation.

#### Inputs

This script does not take any direct inputs from the user. However, it relies on the following environment variables:

*   `OPENWEATHER_API_KEY`: The API key for the OpenWeather API.
*   `SUDO_USER`: The user to configure registry authentication for.

It also requires a pull secret to be present at `/home/lab-user/pullsecret.json`.

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
