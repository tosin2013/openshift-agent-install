#!/bin/bash
set -euo pipefail

# Guard against multiple sourcing
[[ "${CONFIGURE_LVM_SOURCED:-}" == "true" ]] && return 0
CONFIGURE_LVM_SOURCED=true

# Function to print colored output
print_info() { echo -e "\033[0;34m$1\033[0m"; }
print_status() {
    if [ $2 -eq 0 ]; then
        echo -e "\033[0;32m✓ $1\033[0m"
    else
        echo -e "\033[0;31m✗ $1\033[0m"
        return 1
    fi
}
print_section() {
    echo -e "\n\033[1;33m$1\033[0m"
    echo "================================"
}

# Function to configure the LVM volume group and logical volume
configure_vg() {
  print_section "Configuring LVM"

  # Get list of all block devices, excluding those excluded by lsblk, and their sizes
  readarray -t device_info <<< "$(lsblk -l -d -e 11 -n -o NAME,SIZE)"

  declare -A device_sizes

  # Populate an associative array with device sizes and their device paths
  for info in "${device_info[@]}"; do
    device=$(echo "$info" | awk '{print $1}')
    size=$(echo "$info" | awk '{print $2}')
    mount=$(lsblk -no MOUNTPOINT "/dev/$device")

    if [[ -z "$mount" ]]; then  # Check if the device is not mounted
      if [[ -v device_sizes[$size] ]]; then
        device_sizes[$size]="${device_sizes[$size]} /dev/$device"
      else
        device_sizes[$size]="/dev/$device"
      fi
    fi
  done

  # Find the largest size with the most devices
  local largest_size=""
  for size in "${!device_sizes[@]}"; do
    if [[ -z "$largest_size" || "${#device_sizes[$size]}" -gt "${#device_sizes[$largest_size]}" ]]; then
      largest_size=$size
    fi
  done

  # Get the devices with the largest common size
  local unmounted_devices="${device_sizes[$largest_size]}"

  if [[ -z "$unmounted_devices" ]]; then
    print_info "No suitable unmounted devices found."
    return 1
  fi

  print_info "Using devices: $unmounted_devices"

  # Create the physical volume, volume group, and logical volume
  sudo /usr/sbin/pvcreate $unmounted_devices || print_status "Failed to create physical volume" 1
  sudo /usr/sbin/vgcreate vg_qubi $unmounted_devices || print_status "Failed to create volume group vg_qubi" 1
  sudo /usr/sbin/lvcreate -l 100%FREE -n vg_qubi-lv_qubi_images vg_qubi || print_status "Failed to create logical volume" 1

  # Create the filesystem and mount the logical volume
  sudo mkfs.ext4 /dev/vg_qubi/vg_qubi-lv_qubi_images || print_status "Failed to create filesystem" 1
  sudo mkdir -p /var/lib/libvirt/images || print_status "Failed to create directory /var/lib/libvirt/images" 1
  sudo mount /dev/vg_qubi/vg_qubi-lv_qubi_images /var/lib/libvirt/images || print_status "Failed to mount logical volume" 1
  echo "/dev/vg_qubi/vg_qubi-lv_qubi_images /var/lib/libvirt/images ext4 defaults 0 0" | sudo tee -a /etc/fstab || print_status "Failed to update /etc/fstab" 1
  print_status "LVM configured successfully" 0
}

print_section "Setting up libvirt storage pool"

# Check if kvm_pool already exists
if virsh pool-list --all | grep -q "kvm_pool"; then
    print_info "Found existing kvm_pool..."
    # Check pool state
    pool_state=$(virsh pool-info kvm_pool | grep "State" | awk '{print $2}')
    
    case "$pool_state" in
        running)
            print_info "kvm_pool is already active"
            ;;
        inactive)
            print_info "Starting kvm_pool..."
            virsh pool-start kvm_pool || print_status "Failed to start kvm_pool" 1
            ;;
        *)
            print_status "kvm_pool is in an unknown state: $pool_state" 1
            ;;
    esac
    print_status "kvm_pool is ready" 0
else
    # Check if the LVM volume group exists
    if ! sudo /usr/sbin/vgdisplay | grep -q vg_qubi; then
        print_info "vg_qubi not found, configuring LVM..."
        configure_vg
    fi

    # Check if a pool named 'images' already exists
    if virsh pool-list --all | grep -q "images"; then
        print_info "Found existing 'images' pool..."
        # Get the target path of the 'images' pool
        images_target=$(virsh pool-info images | grep "Path" | awk '{print $2}')

        # Check if it points to the same location as our LVM volume
        if [[ "$images_target" == "/var/lib/libvirt/images" ]]; then
            print_info "Using existing 'images' pool."
        else
            print_status "Existing 'images' pool points to a different location ($images_target). Cannot proceed." 1
            exit 1
            virsh pool-list --all
        fi
    else
        print_info "Setting up storage pool using vg_qubi/vg_qubi-lv_qubi_images..."
        # Define a new storage pool using the LVM volume
        virsh pool-define-as --name kvm_pool --type dir --target /var/lib/libvirt/images || print_status "Failed to define storage pool" 1
        virsh pool-build kvm_pool || print_status "Failed to build storage pool" 1
        virsh pool-start kvm_pool || print_status "Failed to start storage pool" 1
        virsh pool-autostart kvm_pool || print_status "Failed to autostart storage pool" 1
        print_status "Storage pool created and started using vg_qubi" 0
    fi
fi
