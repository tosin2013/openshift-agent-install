#!/bin/bash

set -e

# Check if the system is RHEL 9.5
if ! grep -q "Red Hat Enterprise Linux release 9.5" /etc/redhat-release; then
  echo "Error: This script is intended for Red Hat Enterprise Linux 9.5"
  exit 1
fi

echo "Installing Jekyll and dependencies..."

# Install system-level dependencies
echo "Installing system dependencies..."
sudo dnf install -y \
  ruby-devel \
  gcc \
  gcc-c++ \
  make \
  redhat-rpm-config \
  zlib-devel \
  libxml2-devel \
  libxslt-devel

# Set up Ruby environment
echo "Setting up Ruby environment..."
export GEM_HOME="$HOME/.gem"
export PATH="$HOME/.gem/bin:$PATH"

# Install bundler
echo "Installing bundler..."
gem install bundler --user-install || {
  echo "Failed to install bundler"
  exit 1
}

# Change to docs directory
cd "$(dirname "$0")/../docs" || {
  echo "Failed to change to docs directory"
  exit 1
}

# Configure Bundler to install gems to a local directory
echo "Configuring bundler..."
bundle config set --local path 'vendor/bundle'

# Install Jekyll and dependencies using bundler
echo "Installing Jekyll and dependencies..."
bundle install || {
  echo "Failed to install dependencies"
  exit 1
}

echo "Jekyll installation complete! You can now run ./scripts/serve-site.sh to start the development server."
