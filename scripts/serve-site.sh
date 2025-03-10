#!/bin/bash

set -e

# Change to the docs directory
cd docs || exit 1

echo "Cleaning previous builds..."
rm -rf _site .jekyll-cache

echo "Installing dependencies..."
bundle install --path vendor/bundle

echo "Serving site..."
JEKYLL_ENV=production bundle exec jekyll serve \
  --host 0.0.0.0 \
  --baseurl "/openshift-agent-install" \
  --livereload \
  --trace
