#!/usr/bin/env bash

# lin2win-setup.sh: Detect Windows partition and boot entry

echo "Detecting Windows NTFS partitions..."
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -i ntfs

echo "Auto-detecting Windows partition..."
# Look for the largest unmounted NTFS partition (likely Windows C:)
win_part=$(lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT -n | grep ntfs | grep -v "/run/media" | grep -v "/mnt" | sort -k2 -hr | head -1 | awk '{print $1}')

if [ -n "$win_part" ]; then
    # Clean up the partition name (remove tree characters)
    win_part=$(echo "$win_part" | sed 's/[├└│─]*//g')
    echo "Auto-detected Windows partition: $win_part"
    read -p "Use detected partition $win_part? (y/n): " use_detected
    if [[ "$use_detected" != "y" ]]; then
        win_part=""
    fi
fi

if [ -z "$win_part" ]; then
    echo "Could not auto-detect Windows partition or user declined."
    echo "Available NTFS partitions:"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -i ntfs
    read -p "Enter the device name of your Windows partition (e.g., sda3): " win_part
fi

WIN_PART="/dev/$win_part"

echo "Mounting Windows partition..."
sudo mkdir -p /mnt/windows
sudo mount -t ntfs-3g "$WIN_PART" /mnt/windows

echo "Auto-detecting Windows boot entry..."
boot_number=$(efibootmgr | grep -i windows | grep -o 'Boot[0-9A-Fa-f]\{4\}' | head -1 | sed 's/Boot//')

if [ -z "$boot_number" ]; then
    echo "Cannot automatically find Windows boot entry."
    echo "Listing all UEFI boot entries:"
    sudo efibootmgr -v
    read -p "Enter the BootNumber for Windows Boot Manager (e.g., 0001): " boot_number
fi

echo "Found Windows boot entry: $boot_number"

# Save configuration
mkdir -p ~/.config/lin2win
echo "WIN_PART=$WIN_PART" > ~/.config/lin2win/config
echo "WIN_BOOT_ID=$boot_number" >> ~/.config/lin2win/config

# Optional: Setup passwordless efibootmgr
read -p "Setup passwordless efibootmgr for smoother experience? (y/n): " setup_sudo
if [[ "$setup_sudo" == "y" ]]; then
    echo "%wheel ALL=(root) NOPASSWD: /usr/sbin/efibootmgr" | sudo tee /etc/sudoers.d/efibootmgr-config
    echo "Passwordless efibootmgr configured."
fi

echo "Setup complete. Configuration saved to ~/.config/lin2win/config"
echo ""
echo "🎯 Next step: Complete Windows-side setup"
echo "   1. Download this repository in Windows"
echo "   2. Run windows/lin2win-setup.ps1 as Administrator"
echo ""
read -p "Boot into Windows now to complete setup? (y/n): " boot_now

if [[ "$boot_now" == "y" ]]; then
    echo "Setting next boot to Windows..."
    sudo efibootmgr --bootnext "$boot_number"
    echo "Rebooting into Windows in 3 seconds..."
    sleep 3
    sudo reboot
else
    echo "You can boot into Windows later by running: ./lin2win-launch.sh"
fi
