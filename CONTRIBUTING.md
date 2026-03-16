# Contributing to OpenShift Agent Install Helper

Thank you for your interest in contributing to the OpenShift Agent Install Helper project! This document provides a quick overview of the contribution process.

## Repository Overview

Please read our [README.md](README.md) first to understand:
- Project purpose and scope
- Key components and utilities
- Prerequisites and dependencies
- Basic usage instructions

## Repository Structure

```
openshift-agent-install/
├── README.md              # Main project documentation
├── get-rhcos-iso.sh      # RHCOS ISO download utility
├── download-openshift-cli.sh  # OpenShift CLI download utility
├── disconnected-info.md   # Disconnected installation guide
├── docs/                  # Documentation website
├── examples/             # Example configurations
│   ├── baremetal-example/
│   ├── vmware-example/
│   └── sno-examples/
├── playbooks/            # Ansible automation
├── scripts/             # Utility scripts
├── e2e-tests/           # End-to-end tests
├── hack/                # Development scripts
└── site-config/         # Site configuration

```

## Quick Start for Contributors

1. Read the [README.md](README.md) thoroughly
2. Fork the repository
3. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/openshift-agent-install.git
   cd openshift-agent-install
   ```
4. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Prerequisites

As specified in README.md:
- RHEL/CentOS system
- OpenShift CLI tools (`./download-openshift-cli.sh`)
- NMState CLI (`dnf install nmstate`)
- Ansible Core (`dnf install ansible-core`)
- Red Hat OpenShift Pull Secret

For documentation work:
- Ruby 3.2+ and Bundler (see docs/README.md)

## Making Changes

### For Code Changes
1. Follow the examples in the `examples/` directory
2. Use the playbooks in `playbooks/` as templates
3. Add tests in `e2e-tests/` for new features
4. Update relevant documentation

### For Documentation
1. Website changes go in `docs/`
2. Core project documentation updates in:
   - README.md
   - disconnected-info.md
   - Example READMEs

## Testing Your Changes

1. For code changes:
   ```bash
   # Run end-to-end tests
   cd e2e-tests
   ./run-tests.sh

   # Test specific playbooks
   cd playbooks
   ansible-playbook your-playbook.yml
   ```

2. For documentation:
   ```bash
   # Test documentation site
   cd docs
   bundle exec jekyll serve
   ```

## Pull Request Process

1. Update README.md if you've added:
   - New prerequisites
   - New scripts or utilities
   - Changed core functionality
   - Added new examples

2. Ensure your PR includes:
   - Reference to relevant issues
   - Updates to README.md (if needed)
   - Updates to example configurations (if needed)
   - New or updated tests

3. PR Description Template:
   ```markdown
   ## Description
   Brief description of changes

   ## Changes to README.md
   - [ ] No changes needed
   - [ ] Updated prerequisites
   - [ ] Updated usage instructions
   - [ ] Added new feature documentation

   ## Testing Done
   Describe testing performed

   ## Related Issues
   Fixes #issue_number
   ```

## Getting Help

1. Check the [README.md](README.md) first
2. Look for similar examples in `examples/`
3. Check existing issues and discussions
4. Open a new issue if needed

## Additional Documentation

For comprehensive documentation, including:
- Detailed guides
- Architecture decisions
- Advanced configurations
- Best practices

Visit our [documentation website](https://your-org.github.io/openshift-agent-install/).

## Code of Conduct

This project follows the OpenShift community code of conduct. By participating, you are expected to uphold this code. 