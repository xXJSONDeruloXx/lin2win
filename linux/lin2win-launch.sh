#!/usr/bin/env bash

# lin2win-launch.sh: Select and launch Windows executable with smart filtering and search

# Load configuration
if [[ ! -f ~/.config/lin2win/config ]]; then
    echo "Error: Configuration not found. Please run lin2win-setup.sh first."
    exit 1
fi

source ~/.config/lin2win/config

# Smart mount handling - check if already mounted first
MOUNT_POINT=""

echo "Checking Windows partition availability..."

# Check if already mounted at our preferred location
if mountpoint -q /mnt/windows 2>/dev/null; then
    MOUNT_POINT="/mnt/windows"
    echo "Windows partition already mounted at /mnt/windows ✅"
    
# Check if mounted elsewhere
elif EXISTING_MOUNT=$(findmnt -n -o TARGET "$WIN_PART" 2>/dev/null); then
    MOUNT_POINT="$EXISTING_MOUNT"
    echo "Windows partition already mounted at $EXISTING_MOUNT ✅"
    
# Not mounted anywhere - try to mount it
else
    echo "Mounting Windows partition at /mnt/windows..."
    sudo mkdir -p /mnt/windows
    
    if sudo mount -t ntfs-3g "$WIN_PART" /mnt/windows 2>/dev/null; then
        MOUNT_POINT="/mnt/windows"
        echo "Windows partition mounted successfully ✅"
    else
        echo "❌ Failed to mount Windows partition $WIN_PART"
        echo ""
        echo "This could be due to:"
        echo "  • Windows Fast Startup is enabled"
        echo "  • Windows is hibernated"
        echo "  • Partition is already mounted elsewhere"
        echo ""
        echo "Try:"
        echo "  1. Boot into Windows and disable Fast Startup"
        echo "  2. Shutdown Windows completely (not restart)"
        echo "  3. Check if partition is mounted: findmnt $WIN_PART"
        exit 1
    fi
fi

# Verify the mount point has Windows files
if [[ ! -d "$MOUNT_POINT/Windows" ]] || [[ ! -d "$MOUNT_POINT/Program Files" ]]; then
    echo "❌ Mounted partition doesn't appear to contain Windows"
    echo "Mount point: $MOUNT_POINT"
    echo "Contents:"
    ls -la "$MOUNT_POINT/" 2>/dev/null | head -10
    exit 1
fi

echo "Windows partition accessible at: $MOUNT_POINT"
echo ""

# Update all references to use the dynamic mount point instead of hardcoded /mnt/windows
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

# Function to get Windows user directories
get_windows_user_dirs() {
    local user_dirs=()
    
    # Find all user directories in Windows/Users (excluding system accounts)
    if [[ -d "$MOUNT_POINT/Users" ]]; then
        while IFS= read -r -d '' userdir; do
            local username=$(basename "$userdir")
            case "$username" in
                "All Users"|"Default"|"Default User"|"Public"|"desktop.ini")
                    continue ;;
                *)
                    # Add user-specific directories if they exist
                    [[ -d "$userdir/AppData/Local/Programs" ]] && user_dirs+=("Users/$username/AppData/Local/Programs")
                    [[ -d "$userdir/Desktop" ]] && user_dirs+=("Users/$username/Desktop")
                    [[ -d "$userdir/AppData/Roaming" ]] && user_dirs+=("Users/$username/AppData/Roaming")
                    ;;
            esac
        done < <(find "$MOUNT_POINT/Users" -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    
    echo "${user_dirs[@]}"
}

# Function to search for executables (updated to use MOUNT_POINT)
search_executables() {
    local search_term="$1"
    
    # Get Windows user directories dynamically
    local user_dirs=()
    if [[ -d "$MOUNT_POINT/Users" ]]; then
        while IFS= read -r -d '' userdir; do
            local username=$(basename "$userdir")
            case "$username" in
                "All Users"|"Default"|"Default User"|"Public"|"desktop.ini")
                    continue ;;
                *)
                    [[ -d "$userdir/AppData/Local/Programs" ]] && user_dirs+=("Users/$username/AppData/Local/Programs")
                    [[ -d "$userdir/Desktop" ]] && user_dirs+=("Users/$username/Desktop")
                    [[ -d "$userdir/AppData/Roaming" ]] && user_dirs+=("Users/$username/AppData/Roaming")
                    ;;
            esac
        done < <(find "$MOUNT_POINT/Users" -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    
    # Directories to search (in order of priority)
    local search_dirs=(
        "Program Files"
        "Program Files (x86)"
        "Steam/steamapps/common"
        "Epic Games"
        "XboxGames"
        "Games"
        "${user_dirs[@]}"
        "Program Files/Microsoft Office"
        "Program Files (x86)/Microsoft Office"
        "Windows/System32"
        "Program Files/Common Files"
    )
    
    local scored_results=()
    
    # Search through directories
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$MOUNT_POINT/$dir" ]]; then
            # Find executables that match the search term
            while IFS= read -r -d '' exe; do
                if is_user_app "$exe"; then
                    local basename=$(basename "$exe" .exe)
                    local dirname=$(dirname "$exe")
                    
                    # Calculate relevance score
                    local score=0
                    
                    # Exact name match (highest priority)
                    if [[ "${basename,,}" == "${search_term,,}" ]]; then
                        score=100
                    # Name starts with search term
                    elif [[ "${basename,,}" == "${search_term,,}"* ]]; then
                        score=80
                    # Name contains search term
                    elif [[ "${basename,,}" == *"${search_term,,}"* ]]; then
                        score=60
                    # Directory name contains search term
                    elif [[ "${dirname,,}" == *"${search_term,,}"* ]]; then
                        score=40
                    # Fuzzy match (search term words in any order)
                    else
                        local words=($search_term)
                        local match_count=0
                        for word in "${words[@]}"; do
                            if [[ "${basename,,}" == *"${word,,}"* ]] || [[ "${dirname,,}" == *"${word,,}"* ]]; then
                                ((match_count++))
                            fi
                        done
                        if [[ $match_count -gt 0 ]]; then
                            score=$((20 + match_count * 10))
                        fi
                    fi
                    
                    # Boost score for priority directories
                    case "$dir" in
                        "Steam"*|"Epic"*|"Games"*|"Xbox"*)
                            score=$((score + 10)) ;;
                        "Program Files"*|"Users"*)
                            score=$((score + 5)) ;;
                    esac
                    
                    # Only include if there's some relevance
                    if [[ $score -gt 0 ]]; then
                        scored_results+=("$score:$exe")
                    fi
                fi
            done < <(find "$MOUNT_POINT/$dir" -maxdepth 4 -type f -iname "*${search_term}*.exe" -print0 2>/dev/null)
        fi
    done
    
    # Sort by score (descending) and extract file paths
    # Return only the file paths, one per line
    printf '%s\n' "${scored_results[@]}" | sort -nr -t: -k1 | head -50 | cut -d: -f2-
}

# Function to display browse menu
show_browse_menu() {
    # Priority directories for user applications
    local priority_dirs=(
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
    local app_dirs=(
        "Program Files"
        "Program Files (x86)"
        "Users/$USER/AppData/Local/Programs"
        "Users/$USER/Desktop"
    )

    # System directories with useful tools
    local system_dirs=(
        "Windows/System32"
        "Program Files/Common Files"
    )

    declare -a priority_apps=()
    declare -a regular_apps=()
    declare -a system_tools=()

    echo "Scanning priority directories (Games, Steam, Office)..."

    # Scan priority directories first
    for dir in "${priority_dirs[@]}"; do
        if [[ -d "$MOUNT_POINT/$dir" ]]; then
            while IFS= read -r -d '' exe; do
                if is_user_app "$exe"; then
                    priority_apps+=("$exe")
                fi
            done < <(find "$MOUNT_POINT/$dir" -maxdepth 3 -type f -iname "*.exe" -print0 2>/dev/null)
        fi
    done

    echo "Scanning application directories..."

    # Scan regular application directories
    for dir in "${app_dirs[@]}"; do
        if [[ -d "$MOUNT_POINT/$dir" ]]; then
            while IFS= read -r -d '' exe; do
                if is_user_app "$exe"; then
                    # Skip if already found in priority
                    if ! printf '%s\n' "${priority_apps[@]}" | grep -Fxq "$exe"; then
                        regular_apps+=("$exe")
                    fi
                fi
            done < <(find "$MOUNT_POINT/$dir" -maxdepth 2 -type f -iname "*.exe" -print0 2>/dev/null)
        fi
    done

    echo "Scanning system directories for useful tools..."

    # Find some useful system tools
    local useful_tools=(
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
        found=$(find "$MOUNT_POINT" -name "$tool" -type f 2>/dev/null | head -1)
        if [[ -n "$found" ]]; then
            system_tools+=("$found")
        fi
    done

    # Combine and limit results
    local all_apps=()

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
            dir=$(dirname "$exe" | sed "s|$MOUNT_POINT/||" | sed 's|/[^/]*$||')
            printf "%2d) 🎮 %-30s [%s]\n" $((i+1)) "$basename" "$dir"
        fi
    done

    echo ""
    echo "📱 APPLICATIONS:"
    for i in "${!unique_apps[@]}"; do
        exe="${unique_apps[i]}"
        if printf '%s\n' "${regular_apps[@]}" | grep -Fxq "$exe"; then
            basename=$(basename "$exe" .exe)
            dir=$(dirname "$exe" | sed "s|$MOUNT_POINT/||" | sed 's|/[^/]*$||')
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

    echo "${unique_apps[@]}"
}

# Main selection loop
while true; do
    echo ""
    echo "════════════════════════════════════════════"
    echo "🚀 Lin2Win - Windows Application Launcher"
    echo "════════════════════════════════════════════"
    echo ""
    echo "Choose an option:"
    echo "1) 📋 Browse applications (categorized list)"
    echo "2) 🔍 Search for application"
    echo "3) ❌ Exit"
    echo ""
    read -p "Your choice (1-3): " choice

    case $choice in
        1)
            echo ""
            echo "📋 Browsing available applications..."
            readarray -t browse_results < <(show_browse_menu)
            
            if [[ ${#browse_results[@]} -eq 0 ]]; then
                continue
            fi
            
            echo ""
            echo "Select a Windows application to launch:"
            select exe in "${browse_results[@]}" "🔙 Back to main menu"; do
                if [[ "$exe" == "🔙 Back to main menu" ]]; then
                    break
                elif [[ -n "$exe" ]]; then
                    selected_exe="$exe"
                    break 2
                else
                    echo "Invalid selection. Please try again."
                fi
            done
            ;;
        2)
            echo ""
            echo "🔍 Search for Windows applications"
            echo ""
            read -p "Enter search term (app name, keyword, etc.): " search_term
            
            if [[ -z "$search_term" ]]; then
                echo "No search term entered."
                continue
            fi
            
            echo "Searching for applications matching: '$search_term'"
            echo ""
            
            # Capture search results properly
            readarray -t search_results < <(search_executables "$search_term")
            
            if [[ ${#search_results[@]} -eq 0 ]]; then
                echo "No applications found matching '$search_term'"
                echo "Try a different search term or browse applications instead."
                continue
            fi
            
            echo "Found ${#search_results[@]} applications matching '$search_term':"
            echo ""
            
            # Display results cleanly
            for i in "${!search_results[@]}"; do
                exe="${search_results[i]}"
                basename=$(basename "$exe" .exe)
                dir=$(dirname "$exe" | sed "s|$MOUNT_POINT/||")
                printf "%2d) %-40s [%s]\n" $((i+1)) "$basename" "$dir"
            done
            
            echo ""
            echo "Select an application to launch:"
            select exe in "${search_results[@]}" "🔙 Back to main menu"; do
                if [[ "$exe" == "🔙 Back to main menu" ]]; then
                    break
                elif [[ -n "$exe" ]]; then
                    selected_exe="$exe"
                    break 2
                else
                    echo "Invalid selection. Please try again."
                fi
            done
            ;;
        3)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter 1, 2, or 3."
            ;;
    esac
done

# Process the selected executable
exe="$selected_exe"
echo ""
echo "Selected: $(basename "$exe")"

# Convert path to Windows format
win_path="C:$(echo "${exe#$MOUNT_POINT}" | tr '/' '\\')"
echo "Windows path: $win_path"

# Ask user about auto-return
read -p "Automatically return to Linux when application closes? (y/n): " auto_return

# Write the target executable (persistent - stays until manually cleaned)
echo "$win_path" | sudo tee "$MOUNT_POINT/lin2win_target.txt" > /dev/null

# Write launch trigger (persistent - stays until manually cleaned)
echo "launch" | sudo tee "$MOUNT_POINT/launch_on_boot.txt" > /dev/null

# Optionally write return flag (deleted after return)
if [[ "$auto_return" == "y" ]]; then
    echo "enabled" | sudo tee "$MOUNT_POINT/return_to_linux.txt" > /dev/null
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
