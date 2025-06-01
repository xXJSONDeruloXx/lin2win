#!/usr/bin/env bash

# lin2win-setup.sh: Detect Windows partition and boot entry

echo "Detecting Windows NTFS partitions..."
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -i ntfs

read -p "Enter the device name of your Windows partition (e.g., sda3): " win_part
WIN_PART="/dev/$win_part"

echo "Mounting Windows partition..."
sudo mkdir -p /mnt/windows
sudo mount -t ntfs-3g "$WIN_PART" /mnt/windows

echo "Listing UEFI boot entries..."
sudo efibootmgr -v

read -p "Enter the BootNumber for Windows Boot Manager (e.g., 0001): " win_boot_id

# Save configuration
mkdir -p ~/.config/lin2win
echo "WIN_PART=$WIN_PART" > ~/.config/lin2win/config
echo "WIN_BOOT_ID=$win_boot_id" >> ~/.config/lin2win/config

echo "Setup complete. Configuration saved to ~/.config/lin2win/config"
