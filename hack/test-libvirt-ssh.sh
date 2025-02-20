#!/bin/bash
set -e

echo "Testing libvirt connectivity methods..."

# Test basic virsh access with sudo
echo "1. Testing basic virsh access..."
if ! sudo virsh --connect qemu:///system list; then
    echo "Error: Cannot access libvirt with basic virsh command"
    echo "Please ensure libvirtd service is running"
    exit 1
fi

# Test qemu+unix access
echo -e "\n2. Testing qemu+unix access..."
if sudo virsh --connect "qemu+unix:///system" list; then
    echo "Success: Can connect using qemu+unix:///system"
    echo "This might work better with container socket access"
fi

# Test qemu+ssh access
echo -e "\n3. Testing qemu+ssh access..."
if sudo virsh --connect "qemu+ssh://lab-user@localhost/system" list; then
    echo "Success: Can connect using qemu+ssh"
fi

echo -e "\nRecommended configurations for sushy-emulator.conf:"
echo "Option 1 (Unix socket - recommended for container):"
echo "SUSHY_EMULATOR_LIBVIRT_URI = 'qemu+unix:///system'"
echo ""
echo "Option 2 (SSH method - if unix socket fails):"
echo "SUSHY_EMULATOR_LIBVIRT_URI = 'qemu+ssh://lab-user@localhost/system'"
echo ""
echo "Container requirements:" 
echo "- Mount libvirt socket directory: -v /var/run/libvirt:/var/run/libvirt"
echo "- Use --privileged flag or appropriate capabilities"
