---
layout: default
title: Contributing Guide
description: Guide for contributing to the OpenShift Agent Install Helper project and documentation
---

# Contributing Guide

This guide explains how to contribute to both the OpenShift Agent Install Helper project and its documentation website.

## Table of Contents
- [Getting Started](#getting-started)
- [Repository Structure](#repository-structure)
- [Setting Up Development Environment](#setting-up-development-environment)
- [Documentation Website](#documentation-website)
- [Making Contributions](#making-contributions)
- [Pull Request Process](#pull-request-process)
- [Style Guides](#style-guides)

## Getting Started

### Prerequisites
- Git
- Ruby 3.2 or later (for documentation website)
- Bundler
- Text editor
- GitHub account

### Quick Start
```bash
# Clone the repository
git clone https://github.com/your-org/openshift-agent-install.git
cd openshift-agent-install

# Set up documentation website locally
./scripts/install-jekyll.sh
./scripts/serve-site.sh
```

## Repository Structure

```
openshift-agent-install/
├── docs/                    # Documentation website
│   ├── _config.yml         # Jekyll configuration
│   ├── adr/                # Architecture Decision Records
│   ├── assets/             # Images and other assets
│   └── *.md               # Documentation pages
├── examples/               # Example configurations
├── playbooks/             # Ansible playbooks
├── scripts/               # Utility scripts
├── e2e-tests/             # End-to-end tests
├── hack/                  # Development scripts
└── site-config/           # Site configuration files
```

## Setting Up Development Environment

### For Documentation Website
1. Install Ruby and Bundler:
   ```bash
   # On RHEL/CentOS
   sudo dnf install ruby ruby-devel
   gem install bundler

   # On Ubuntu/Debian
   sudo apt-get install ruby ruby-dev
   gem install bundler
   ```

2. Install Jekyll and dependencies:
   ```bash
   ./scripts/install-jekyll.sh
   ```

3. Start local server:
   ```bash
   ./scripts/serve-site.sh
   ```

4. Visit `http://localhost:4000/openshift-agent-install/`

### For Project Development
1. Set up Python environment (if needed)
2. Install Ansible
3. Configure development tools

## Documentation Website

### Adding New Pages

1. Create a new Markdown file in `docs/`:
   ```markdown
   ---
   layout: default
   title: Your Page Title
   description: Brief description of the page
   ---

   # Your Page Title
   Content goes here...
   ```

2. Add to navigation:
   - Update relevant section in `docs/index.md`
   - Link from related pages

### Adding ADRs

1. Copy template from existing ADR
2. Number sequentially
3. Add front matter:
   ```markdown
   ---
   layout: default
   title: "ADR-XXXX: Your ADR Title"
   description: "Architecture Decision Record for..."
   ---
   ```
4. Update `docs/adr/index.md`

### Local Testing
```bash
cd docs
bundle exec jekyll serve --host 0.0.0.0 --port 4000 --baseurl /openshift-agent-install
```

## Making Contributions

### Branch Strategy
- `main`: Primary branch
- `feature/*`: New features
- `fix/*`: Bug fixes
- `docs/*`: Documentation updates

### Commit Messages
```
type(scope): Brief description

Detailed description of changes
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructuring
- `test`: Adding tests
- `chore`: Maintenance

### Documentation Changes
1. Make changes in `docs/` directory
2. Test locally
3. Commit with `docs:` prefix
4. Create pull request

### Code Changes
1. Create feature branch
2. Make changes
3. Add tests
4. Update documentation
5. Create pull request

## Pull Request Process

1. **Before Creating PR**
   - Test changes locally
   - Update documentation
   - Add tests if needed
   - Ensure CI passes

2. **PR Description**
   ```markdown
   ## Description
   Brief description of changes

   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Other (specify)

   ## Testing Done
   Describe testing performed

   ## Documentation
   - [ ] Documentation updated
   - [ ] No documentation needed
   ```

3. **Review Process**
   - Automated checks must pass
   - At least one maintainer review
   - Documentation review if needed

4. **After Merge**
   - Delete feature branch
   - Update related issues
   - Monitor deployment

## Style Guides

### Documentation Style
- Use American English
- Write in present tense
- Use active voice
- Include code examples
- Add screenshots for UI changes

### Markdown Guidelines
- Use ATX headers (`#` style)
- Code blocks with language
- Tables for structured data
- Links for references

### Code Style
- Follow language conventions
- Document public APIs
- Include comments
- Use consistent naming

## GitHub Pages

The documentation is automatically deployed to GitHub Pages when changes are merged to `main`. The deployment process:

1. GitHub Action builds site
2. Deploys to GitHub Pages
3. Available at project URL

### Troubleshooting Deployments
- Check Actions tab for build logs
- Verify front matter in Markdown files
- Test locally before pushing
- Check Jekyll configuration

## Getting Help

- Open an issue for questions
- Join project discussions
- Contact maintainers
- Review existing documentation

## Additional Resources

- [Jekyll Documentation](https://jekyllrb.com/docs/)
- [GitHub Pages Documentation](https://docs.github.com/en/pages)
- [Markdown Guide](https://www.markdownguide.org/)
- [OpenShift Documentation](https://docs.openshift.com/) 