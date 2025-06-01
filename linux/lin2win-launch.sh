#!/usr/bin/env bash

# lin2win-launch.sh: Select and launch Windows executable

# Load configuration
if [[ ! -f ~/.config/lin2win/config ]]; then
    echo "Error: Configuration not found. Please run lin2win-setup.sh first."
    exit 1
fi

source ~/.config/lin2win/config

# Mount Windows partition
echo "Mounting Windows partition..."
sudo mkdir -p /mnt/windows
if ! sudo mount -t ntfs-3g "$WIN_PART" /mnt/windows; then
    echo "Error: Failed to mount Windows partition $WIN_PART"
    exit 1
fi

# Check if Windows directories exist
if [[ ! -d "/mnt/windows" ]]; then
    echo "Error: Windows partition not accessible"
    exit 1
fi

echo "Windows partition mounted. Contents:"
ls -la /mnt/windows/

# Find .exe files in multiple common locations
echo "Searching for .exe files..."
mapfile -t exe_files < <(find /mnt/windows -type f -iname "*.exe" \
    \( -path "*/Program Files*" -o -path "*/Program Files (x86)*" -o -path "*/Games*" -o -path "*/Steam*" \) \
    2>/dev/null | head -50)

# Check if any executables were found
if [[ ${#exe_files[@]} -eq 0 ]]; then
    echo "No .exe files found in common program directories."
    echo "Let's search more broadly..."
    
    # Broader search (but limit results)
    mapfile -t exe_files < <(find /mnt/windows -type f -iname "*.exe" 2>/dev/null | head -20)
    
    if [[ ${#exe_files[@]} -eq 0 ]]; then
        echo "No .exe files found on Windows partition."
        echo "Please check if Windows is properly mounted at /mnt/windows"
        ls -la /mnt/windows/
        exit 1
    fi
fi

echo "Found ${#exe_files[@]} executable(s):"

# Select executable
echo "Select a Windows executable to launch:"
select exe in "${exe_files[@]}" "Cancel"; do
    if [[ "$exe" == "Cancel" ]]; then
        echo "Cancelled."
        exit 0
    elif [[ -n "$exe" ]]; then
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

echo "Selected: $exe"

# Convert path to Windows format
win_path="C:$(echo "${exe#/mnt/windows}" | tr '/' '\\')"

echo "Windows path: $win_path"

# Write launch instruction
echo "$win_path" | sudo tee /mnt/windows/launch_on_boot.txt > /dev/null

# Set next boot to Windows
sudo efibootmgr --bootnext "$WIN_BOOT_ID"

# Reboot
echo "Rebooting into Windows to launch: $win_path"
sleep 2
sudo reboot
