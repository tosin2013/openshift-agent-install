#!/bin/bash
set -e

# Check if sushy-bmc interface exists
if ! ip link show sushy-bmc &> /dev/null; then
    echo "Creating sushy-bmc interface..."
    sudo ip link add sushy-bmc link virbr0 type macvlan mode bridge
    sudo ip addr add 192.168.122.10/24 dev sushy-bmc
    sudo ip link set sushy-bmc up
else
    echo "sushy-bmc interface already exists"
fi

echo "Configuring sushy-emulator with unix socket access..."

if systemctl is-active --quiet firewalld; then
    # Check if port 8000 is already added to libvirt zone
    if ! firewall-cmd --zone=libvirt --query-port=8000/tcp; then
        echo "Adding firewall rules..."
        firewall-cmd --zone=libvirt --add-port=8000/tcp --permanent
        firewall-cmd --permanent --zone=trusted --add-interface=sushy-bmc
        firewall-cmd --permanent --add-port=8000/tcp
        firewall-cmd --reload
        firewall-cmd --list-all --zone=libvirt
    else
        echo "Firewall rules already exist, skipping..."
    fi
fi

# Create or update configuration
echo "1. Creating sushy-emulator configuration..."
sudo mkdir -p /etc/sushy
sudo tee /etc/sushy/sushy-emulator.conf << EOF
SUSHY_EMULATOR_LISTEN_IP = '192.168.122.10'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_SSL_CERT = None
SUSHY_EMULATOR_SSL_KEY = None
SUSHY_EMULATOR_OS_CLOUD = None
SUSHY_EMULATOR_LIBVIRT_URI = 'qemu+unix:///system'
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = True
SUSHY_EMULATOR_INTERFACE_NAME = 'sushy-bmc'
SUSHY_EMULATOR_BOOT_LOADER_MAP = {
    'UEFI': {
        'x86_64': '/usr/share/OVMF/OVMF_CODE.secboot.fd'
    },
    'Legacy': {
        'x86_64': None
    }
}
EOF

# Stop existing container if running
echo "2. Cleaning up existing container..."
sudo podman rm -f sushy-emulator || true

# Start new container with unix socket access
echo "3. Starting sushy-emulator container..."
sudo podman create --name sushy-emulator \
    --network=host \
    --privileged \
    -v "/etc/sushy":/etc/sushy:Z \
    -v "/var/run/libvirt":/var/run/libvirt:Z \
    quay.io/metal3-io/sushy-tools \
    sushy-emulator -i 192.168.122.10 -p 8000 --config /etc/sushy/sushy-emulator.conf

# Create and start systemd service
echo "4. Setting up systemd service..."
sudo podman generate systemd --restart-policy=always --new -n sushy-emulator > /etc/systemd/system/sushy-emulator.service
sudo systemctl daemon-reload
sudo systemctl enable --now sushy-emulator

# Check container logs
echo "5. Checking container logs..."
sleep 2
sudo podman logs sushy-emulator

# Test connectivity
echo "6. Testing connectivity..."
timeout=30
while [ $timeout -gt 0 ]; do
    if curl -sf http://192.168.122.10:8000/redfish/v1/Systems > /dev/null; then
        echo "Success! Sushy-emulator is running and accessible"
        echo "Testing API response:"
        curl -s http://192.168.122.10:8000/redfish/v1/Systems | python3 -m json.tool
        exit 0
    fi
    echo "Waiting... ${timeout}s remaining"
    sleep 1
    ((timeout--))
done

echo "Error: Timeout waiting for sushy-emulator"
echo "Container logs:"
sudo podman logs sushy-emulator
exit 1
