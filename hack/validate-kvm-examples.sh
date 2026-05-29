#!/bin/bash
# validate-kvm-examples.sh
# Validates KVM examples have correct DNS and VLAN configuration

set -e

REQUIRED_DNS="192.168.122.1"
REQUIRED_VLAN="1924"
REQUIRED_NETWORK="192.168.50.0/24"
REQUIRED_GATEWAY="192.168.50.1"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR/.."

echo "============================================================================"
echo "KVM Example Configuration Validation"
echo "============================================================================"
echo "Required Configuration:"
echo "  DNS Server: $REQUIRED_DNS (libvirt dnsmasq)"
echo "  VLAN: $REQUIRED_VLAN"
echo "  Network: $REQUIRED_NETWORK"
echo "  Gateway: $REQUIRED_GATEWAY (VyOS)"
echo "============================================================================"
echo ""

total_examples=0
passing_examples=0
failing_examples=0

for dir in examples/*/; do
  cluster_yml="${dir}cluster.yml"
  nodes_yml="${dir}nodes.yml"

  if [ ! -f "$cluster_yml" ]; then
    continue
  fi

  # Check platform type (only validate KVM-compatible examples)
  platform=$(grep "platform_type:" "$cluster_yml" | awk '{print $2}' | tr -d '"' 2>/dev/null || echo "")
  if [ "$platform" != "none" ] && [ "$platform" != "baremetal" ]; then
    continue
  fi

  total_examples=$((total_examples + 1))
  example_name=$(basename "$dir")

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📁 $example_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  issues_found=0

  # Check ocp_version exists
  ocp_version=$(grep "^ocp_version:" "$cluster_yml" | awk '{print $2}' | tr -d '"' || echo "")
  if [ -z "$ocp_version" ]; then
    echo "  ⚠️  WARNING: No ocp_version specified (required for version validation)"
  else
    echo "  ✅ OCP Version: $ocp_version"
  fi

  # Check DNS
  dns=$(grep -A1 "dns_servers:" "$cluster_yml" | grep -E "^\s*-\s*" | awk '{print $2}' | head -1)
  if [ "$dns" != "$REQUIRED_DNS" ]; then
    echo "  ❌ DNS: $dns → should be $REQUIRED_DNS"
    issues_found=$((issues_found + 1))
  else
    echo "  ✅ DNS: $dns"
  fi

  # Check machine network
  network=$(grep "machine_network_cidrs:" -A1 "$cluster_yml" | grep -E "^\s*-\s*" | awk '{print $2}' | head -1)
  if [ "$network" != "$REQUIRED_NETWORK" ]; then
    echo "  ❌ Network: $network → should be $REQUIRED_NETWORK"
    issues_found=$((issues_found + 1))
  else
    echo "  ✅ Network: $network"
  fi

  # Check VIPs are in correct network
  api_vip=$(grep "api_vips:" -A1 "$cluster_yml" | grep -E "^\s*-\s*" | awk '{print $2}' | head -1)
  if [[ ! "$api_vip" =~ ^192\.168\.50\. ]]; then
    echo "  ❌ API VIP: $api_vip → should be in 192.168.50.0/24"
    issues_found=$((issues_found + 1))
  else
    echo "  ✅ API VIP: $api_vip"
  fi

  app_vip=$(grep "app_vips:" -A1 "$cluster_yml" | grep -E "^\s*-\s*" | awk '{print $2}' | head -1)
  if [[ ! "$app_vip" =~ ^192\.168\.50\. ]]; then
    echo "  ❌ App VIP: $app_vip → should be in 192.168.50.0/24"
    issues_found=$((issues_found + 1))
  else
    echo "  ✅ App VIP: $app_vip"
  fi

  # Check rendezvous IP
  rendezvous_ip=$(grep "rendezvous_ip:" "$cluster_yml" | awk '{print $2}' | head -1)
  if [[ ! "$rendezvous_ip" =~ ^192\.168\.50\. ]]; then
    echo "  ❌ Rendezvous IP: $rendezvous_ip → should be in 192.168.50.0/24"
    issues_found=$((issues_found + 1))
  else
    echo "  ✅ Rendezvous IP: $rendezvous_ip"
  fi

  # Check VLAN in nodes.yml
  if [ -f "$nodes_yml" ]; then
    vlan=$(grep "id:" "$nodes_yml" | awk '{print $2}' | head -1)
    if [ -n "$vlan" ] && [ "$vlan" != "$REQUIRED_VLAN" ]; then
      echo "  ❌ VLAN: $vlan → should be $REQUIRED_VLAN"
      issues_found=$((issues_found + 1))
    elif [ -n "$vlan" ]; then
      echo "  ✅ VLAN: $vlan"
    else
      echo "  ⚠️  VLAN: not configured (may be using non-VLAN interface)"
    fi

    # Check node IPs are in correct network
    node_ips=$(grep -E "ip:\s*192\." "$nodes_yml" | awk '{print $2}' | head -3)
    if [ -n "$node_ips" ]; then
      for ip in $node_ips; do
        if [[ ! "$ip" =~ ^192\.168\.50\. ]]; then
          echo "  ❌ Node IP: $ip → should be in 192.168.50.0/24"
          issues_found=$((issues_found + 1))
        fi
      done
      if [ $issues_found -eq 0 ]; then
        echo "  ✅ Node IPs: in 192.168.50.0/24"
      fi
    fi

    # Check gateway
    gateway=$(grep "next-hop-address:" "$nodes_yml" | awk '{print $2}' | head -1)
    if [ -n "$gateway" ] && [ "$gateway" != "$REQUIRED_GATEWAY" ]; then
      echo "  ❌ Gateway: $gateway → should be $REQUIRED_GATEWAY"
      issues_found=$((issues_found + 1))
    elif [ -n "$gateway" ]; then
      echo "  ✅ Gateway: $gateway"
    fi
  fi

  # Summary for this example
  if [ $issues_found -eq 0 ]; then
    echo "  ✅ PASSED: All checks passed"
    passing_examples=$((passing_examples + 1))
  else
    echo "  ❌ FAILED: $issues_found issue(s) found"
    failing_examples=$((failing_examples + 1))
  fi

  echo ""
done

echo "============================================================================"
echo "Summary"
echo "============================================================================"
echo "Total Examples: $total_examples"
echo "✅ Passing: $passing_examples"
echo "❌ Failing: $failing_examples"
echo "============================================================================"

if [ $failing_examples -gt 0 ]; then
  exit 1
else
  echo "All examples passed validation!"
  exit 0
fi
