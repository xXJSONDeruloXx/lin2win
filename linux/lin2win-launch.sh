#!/usr/bin/env bash

# lin2win-launch.sh: Select and launch Windows executable

# Load configuration
source ~/.config/lin2win/config

# Mount Windows partition
sudo mount -t ntfs-3g "$WIN_PART" /mnt/windows

# Find .exe files
echo "Searching for .exe files..."
mapfile -t exe_files < <(find /mnt/windows/Program\ Files* -type f -iname "*.exe" 2>/dev/null)

# Select executable
echo "Select a Windows executable to launch:"
select exe in "${exe_files[@]}"; do
    if [[ -n "$exe" ]]; then
        break
    else
        echo "Invalid selection."
    fi
done

# Convert path to Windows format
win_path="C:$(echo "${exe#/mnt/windows}" | tr '/' '\\')"

# Write launch instruction
echo "$win_path" | sudo tee /mnt/windows/launch_on_boot.txt

# Set next boot to Windows
sudo efibootmgr --bootnext "$WIN_BOOT_ID"

# Reboot
echo "Rebooting into Windows..."
sudo reboot
