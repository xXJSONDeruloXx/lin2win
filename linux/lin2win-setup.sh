#!/usr/bin/env bash

# lin2win-setup.sh: Detect Windows partition and boot entry

echo "Detecting Windows NTFS partitions..."
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -i ntfs

read -p "Enter the device name of your Windows partition (e.g., sda3): " win_part
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
