# Scripts Directory

This directory contains utility scripts for the OpenShift Agent Install Helper project. These scripts help with documentation site management, installation processes, and validation tasks.

## Available Scripts

### Documentation Site Management
- `install-jekyll.sh`: Sets up the Jekyll environment for the documentation site
- `serve-site.sh`: Runs the documentation site locally for testing

### Root Directory Scripts
- `get-rhcos-iso.sh`: Downloads RHCOS ISO images for OpenShift installation
- `download-openshift-cli.sh`: Downloads and sets up OpenShift CLI tools

## Usage

### Setting up the Documentation Site
```bash
# Install Jekyll and dependencies
./scripts/install-jekyll.sh

# Serve the documentation site locally
./scripts/serve-site.sh
```

### Installation Tools
```bash
# Download RHCOS ISO
./get-rhcos-iso.sh

# Download OpenShift CLI
./download-openshift-cli.sh
```

## Script Descriptions

### install-jekyll.sh
Sets up the Ruby environment and installs all necessary dependencies for running the Jekyll documentation site. This script:
- Installs Ruby if not present
- Sets up Bundler
- Installs required gems
- Configures the Jekyll environment

### serve-site.sh
Runs the documentation site locally for testing and development. This script:
- Changes to the docs directory
- Starts Jekyll in development mode
- Makes the site available at http://localhost:4000/openshift-agent-install/

### get-rhcos-iso.sh
Downloads the Red Hat CoreOS (RHCOS) ISO required for OpenShift installation. Located in the root directory.

### download-openshift-cli.sh
Downloads and sets up the OpenShift CLI tools. Located in the root directory.

## Adding New Scripts

When adding new scripts to this directory:
1. Use descriptive names that indicate the script's purpose
2. Add proper documentation within the script
3. Update this README.md with the new script's details
4. Ensure the script has proper execute permissions
5. Add any necessary dependencies to the documentation

## Testing

All scripts should be tested in both connected and disconnected environments. Use the validation tools in the `e2e-tests/` directory to verify script functionality.

## Maintenance

Scripts in this directory are maintained by the project maintainers. If you find issues or have suggestions for improvements, please:
1. Open an issue describing the problem or enhancement
2. Submit a pull request with the proposed changes
3. Ensure all changes are documented
4. Update related documentation if necessary 