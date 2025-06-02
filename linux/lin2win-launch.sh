#!/usr/bin/env bash

# lin2win-launch.sh: Select and launch Windows executable with smart filtering

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

echo "Windows partition mounted. Searching for applications..."

# Function to filter out unwanted executables
is_user_app() {
    local exe="$1"
    local basename=$(basename "$exe" .exe)
    
    # Skip known system/utility patterns
    case "$basename" in
        # Installers and setup tools
        *install*|*setup*|*uninstall*|*update*|installer*|7z|winrar|*extract*)
            return 1 ;;
        # System utilities
        *crash*|*handler*|*dump*|*log*|*monitor*|*service*|*daemon*)
            return 1 ;;
        # Development tools
        *debug*|*test*|*dev*|node*|*compiler*|*build*)
            return 1 ;;
        # Driver components
        AMD*|*driver*|*inf*|*sys*|*dll*)
            return 1 ;;
        # Background processes
        *svc*|*srv*|*helper*|*agent*|*background*|*launcher*)
            return 1 ;;
        # Temporary/cache files
        *temp*|*tmp*|*cache*|*cleanup*)
            return 1 ;;
    esac
    return 0
}

# Priority directories for user applications
priority_dirs=(
    "Steam/steamapps/common"
    "Epic Games"
    "Program Files/Steam"
    "Program Files (x86)/Steam"
    "XboxGames"
    "Games"
    "Program Files/Microsoft Office"
    "Program Files (x86)/Microsoft Office"
)

# Common application directories
app_dirs=(
    "Program Files"
    "Program Files (x86)"
    "Users/$USER/AppData/Local/Programs"
    "Users/$USER/Desktop"
)

# System directories with useful tools
system_dirs=(
    "Windows/System32"
    "Program Files/Common Files"
)

declare -a priority_apps=()
declare -a regular_apps=()
declare -a system_tools=()

echo "Scanning priority directories (Games, Steam, Office)..."

# Scan priority directories first
for dir in "${priority_dirs[@]}"; do
    if [[ -d "/mnt/windows/$dir" ]]; then
        while IFS= read -r -d '' exe; do
            if is_user_app "$exe"; then
                priority_apps+=("$exe")
            fi
        done < <(find "/mnt/windows/$dir" -maxdepth 3 -type f -iname "*.exe" -print0 2>/dev/null)
    fi
done

echo "Scanning application directories..."

# Scan regular application directories
for dir in "${app_dirs[@]}"; do
    if [[ -d "/mnt/windows/$dir" ]]; then
        while IFS= read -r -d '' exe; do
            if is_user_app "$exe"; then
                # Skip if already found in priority
                if ! printf '%s\n' "${priority_apps[@]}" | grep -Fxq "$exe"; then
                    regular_apps+=("$exe")
                fi
            fi
        done < <(find "/mnt/windows/$dir" -maxdepth 2 -type f -iname "*.exe" -print0 2>/dev/null)
    fi
done

echo "Scanning system directories for useful tools..."

# Find some useful system tools
useful_tools=(
    "msinfo32.exe"
    "calc.exe"
    "notepad.exe"
    "mspaint.exe"
    "explorer.exe"
    "cmd.exe"
    "powershell.exe"
    "regedit.exe"
    "taskmgr.exe"
    "control.exe"
    "winver.exe"
    "dxdiag.exe"
)

for tool in "${useful_tools[@]}"; do
    found=$(find "/mnt/windows" -name "$tool" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        system_tools+=("$found")
    fi
done

# Combine and limit results
all_apps=()

# Add priority apps first (games, major software)
for app in "${priority_apps[@]:0:15}"; do
    all_apps+=("$app")
done

# Add regular apps
for app in "${regular_apps[@]:0:20}"; do
    all_apps+=("$app")
done

# Add useful system tools
for tool in "${system_tools[@]}"; do
    all_apps+=("$tool")
done

# Remove duplicates and limit total
readarray -t unique_apps < <(printf '%s\n' "${all_apps[@]}" | sort -u | head -40)

if [[ ${#unique_apps[@]} -eq 0 ]]; then
    echo "No suitable applications found."
    echo "This might happen if Windows Fast Startup is enabled or the partition is hibernated."
    echo "Try disabling Fast Startup in Windows and shutting down completely."
    exit 1
fi

echo ""
echo "Found ${#unique_apps[@]} applications:"
echo ""

# Enhanced display with categories
echo "🎮 GAMES & MAJOR APPLICATIONS:"
for i in "${!unique_apps[@]}"; do
    exe="${unique_apps[i]}"
    if printf '%s\n' "${priority_apps[@]}" | grep -Fxq "$exe"; then
        basename=$(basename "$exe" .exe)
        dir=$(dirname "$exe" | sed 's|/mnt/windows/||' | sed 's|/[^/]*$||')
        printf "%2d) 🎮 %-30s [%s]\n" $((i+1)) "$basename" "$dir"
    fi
done

echo ""
echo "📱 APPLICATIONS:"
for i in "${!unique_apps[@]}"; do
    exe="${unique_apps[i]}"
    if printf '%s\n' "${regular_apps[@]}" | grep -Fxq "$exe"; then
        basename=$(basename "$exe" .exe)
        dir=$(dirname "$exe" | sed 's|/mnt/windows/||' | sed 's|/[^/]*$||')
        printf "%2d) 📱 %-30s [%s]\n" $((i+1)) "$basename" "$dir"
    fi
done

echo ""
echo "🔧 SYSTEM TOOLS:"
for i in "${!unique_apps[@]}"; do
    exe="${unique_apps[i]}"
    if printf '%s\n' "${system_tools[@]}" | grep -Fxq "$exe"; then
        basename=$(basename "$exe" .exe)
        printf "%2d) 🔧 %-30s [System]\n" $((i+1)) "$basename"
    fi
done

echo ""
echo "Select a Windows application to launch:"
select exe in "${unique_apps[@]}" "Cancel"; do
    if [[ "$exe" == "Cancel" ]]; then
        echo "Cancelled."
        exit 0
    elif [[ -n "$exe" ]]; then
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

echo "Selected: $(basename "$exe")"

# Convert path to Windows format
win_path="C:$(echo "${exe#/mnt/windows}" | tr '/' '\\')"
echo "Windows path: $win_path"

# Ask user about auto-return
read -p "Automatically return to Linux when application closes? (y/n): " auto_return

# Write the target executable (persistent - stays until manually cleaned)
echo "$win_path" | sudo tee /mnt/windows/lin2win_target.txt > /dev/null

# Write launch trigger (deleted after launch)
echo "launch" | sudo tee /mnt/windows/launch_on_boot.txt > /dev/null

# Optionally write return flag (deleted after return)
if [[ "$auto_return" == "y" ]]; then
    echo "enabled" | sudo tee /mnt/windows/return_to_linux.txt > /dev/null
    echo "Auto-return enabled: Will return to Linux when $(basename "$exe") closes"
else
    echo "Auto-return disabled: Will stay in Windows after application closes"
fi

# Set next boot to Windows
sudo efibootmgr --bootnext "$WIN_BOOT_ID"

# Reboot
echo "Rebooting into Windows to launch: $(basename "$exe")"
sleep 2
sudo reboot
