#!/bin/bash
# fix-kvm-dns.sh
# Batch update DNS servers in KVM examples to use libvirt dnsmasq (192.168.122.1)

set -e

REQUIRED_DNS="192.168.122.1"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

echo "============================================================================"
echo "Fixing DNS Configuration in KVM Examples"
echo "============================================================================"
echo "Target DNS Server: $REQUIRED_DNS (libvirt dnsmasq)"
echo "============================================================================"
echo ""

updated_count=0
skipped_count=0

for dir in examples/*/; do
  cluster_yml="${dir}cluster.yml"

  if [ ! -f "$cluster_yml" ]; then
    continue
  fi

  # Check platform type
  platform=$(grep "platform_type:" "$cluster_yml" | awk '{print $2}' | tr -d '"' 2>/dev/null || echo "")
  if [ "$platform" != "none" ] && [ "$platform" != "baremetal" ]; then
    continue
  fi

  example_name=$(basename "$dir")

  # Check current DNS
  current_dns=$(grep -A1 "dns_servers:" "$cluster_yml" | grep -E "^\s*-\s*" | awk '{print $2}' | head -1)

  if [ "$current_dns" = "$REQUIRED_DNS" ]; then
    echo "✅ $example_name - Already correct ($current_dns)"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  echo "🔧 $example_name - Updating DNS: $current_dns → $REQUIRED_DNS"

  # Backup
  cp "$cluster_yml" "${cluster_yml}.bak"

  # Update DNS using sed
  # Find the dns_servers section and replace the first IP address
  sed -i "/dns_servers:/,/^\s*-\s*[0-9]/ {
    s/^\s*-\s*[0-9][0-9.]*$/  - $REQUIRED_DNS/
  }" "$cluster_yml"

  # Verify the change
  new_dns=$(grep -A1 "dns_servers:" "$cluster_yml" | grep -E "^\s*-\s*" | awk '{print $2}' | head -1)

  if [ "$new_dns" = "$REQUIRED_DNS" ]; then
    echo "   ✅ Updated successfully"
    updated_count=$((updated_count + 1))
  else
    echo "   ❌ Update failed, restoring backup"
    mv "${cluster_yml}.bak" "$cluster_yml"
  fi

  echo ""
done

echo "============================================================================"
echo "Summary"
echo "============================================================================"
echo "Updated: $updated_count examples"
echo "Skipped: $skipped_count examples (already correct)"
echo "============================================================================"

if [ $updated_count -gt 0 ]; then
  echo ""
  echo "✅ DNS configuration updated!"
  echo ""
  echo "Next steps:"
  echo "1. Review changes: git diff examples/"
  echo "2. Test deployments with updated examples"
  echo "3. Commit changes: git add examples/ && git commit -m 'fix: Standardize DNS to libvirt dnsmasq (192.168.122.1)'"
  echo "4. Run validation: ./hack/validate-kvm-examples.sh"
fi
