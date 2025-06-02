#!/usr/bin/env bash
set -euo pipefail

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

###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––
###  Steam Games Detection Functions
###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––

# Function to parse Steam's libraryfolders.vdf and appmanifest files
parse_steam_games() {
    local steam_root="$MOUNT_POINT/Program Files (x86)/Steam"
    local vdf_file="$steam_root/steamapps/libraryfolders.vdf"
    
    # Check if Steam is installed
    if [[ ! -f "$vdf_file" ]]; then
        # Try alternative Steam location
        steam_root="$MOUNT_POINT/Program Files/Steam"
        vdf_file="$steam_root/steamapps/libraryfolders.vdf"
        if [[ ! -f "$vdf_file" ]]; then
            return 1
        fi
    fi

    local lib_paths=()
    
    # Parse libraryfolders.vdf to find all Steam library paths
    while IFS= read -r line; do
        if [[ $line =~ \"[0-9]+\"[[:space:]]+\"([A-Z]:(\\\\|/).*)\" ]]; then
            raw_path="${BASH_REMATCH[1]}"
            # Convert Windows path to Linux mount path
            drive="${raw_path:0:1}"
            rest="${raw_path:2}"
            rest="${rest//\\//}"
            lib_paths+=("$MOUNT_POINT/${drive}${rest}/steamapps")
        fi
    done < <(grep -E '^\s*"[0-9]+"\s+"[A-Z]:' "$vdf_file" 2>/dev/null || true)

    # Also include the default Steam install folder
    lib_paths+=("$steam_root/steamapps")

    # Parse each library for installed games
    for steamapps in "${lib_paths[@]}"; do
        [[ -d "$steamapps" ]] || continue
        
        while IFS= read -r -d '' acf; do
            local name installdir
            name="$(grep -m1 '"name"' "$acf" 2>/dev/null | sed -E 's/.*"name"[[:space:]]+"(.*)".*/\1/' || true)"
            installdir="$(grep -m1 '"installdir"' "$acf" 2>/dev/null | sed -E 's/.*"installdir"[[:space:]]+"(.*)".*/\1/' || true)"
            
            [[ -z "$name" || -z "$installdir" ]] && continue

            local common_folder="$steamapps/common/$installdir"
            if [[ -d "$common_folder" ]]; then
                local exe_path=""
                
                # Try to find the main executable
                if [[ -f "$common_folder/${installdir}.exe" ]]; then
                    exe_path="$common_folder/${installdir}.exe"
                else
                    # Find any .exe in the game folder (prioritize root level)
                    exe_path="$(find "$common_folder" -maxdepth 2 -type f -iname "*.exe" | head -n1 2>/dev/null || true)"
                fi
                
                [[ -n "$exe_path" ]] && printf '%s|%s\n' "$name" "$exe_path"
            fi
        done < <(find "$steamapps" -maxdepth 1 -type f -iname "appmanifest_*.acf" -print0 2>/dev/null || true)
    done
}

# Function to parse Epic Games installations
parse_epic_games() {
    local epic_manifests="$MOUNT_POINT/ProgramData/Epic/EpicGamesLauncher/Data/Manifests"
    
    [[ -d "$epic_manifests" ]] || return 1
    
    while IFS= read -r -d '' manifest; do
        local display_name install_location launch_exe
        
        # Extract fields from JSON manifest
        display_name="$(grep -o '"DisplayName"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest" 2>/dev/null | sed 's/.*"DisplayName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
        install_location="$(grep -o '"InstallLocation"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest" 2>/dev/null | sed 's/.*"InstallLocation"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
        launch_exe="$(grep -o '"LaunchExecutable"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest" 2>/dev/null | sed 's/.*"LaunchExecutable"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
        
        if [[ -n "$display_name" && -n "$install_location" && -n "$launch_exe" ]]; then
            # Convert Windows path to mount path
            local mount_location="${install_location//\\//}"
            mount_location="$MOUNT_POINT/${mount_location#*:}"
            local exe_path="$mount_location/$launch_exe"
            
            [[ -f "$exe_path" ]] && printf '%s|%s\n' "$display_name" "$exe_path"
        fi
    done < <(find "$epic_manifests" -maxdepth 1 -type f -iname "*.item" -print0 2>/dev/null || true)
}

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

###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––
###  Executable Indexing Functions
###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––

# Function to build a comprehensive index of all executables
build_executable_index() {
    local index_file="$1"
    >"$index_file"

    echo "Building executable index..."

    # 1. Steam games
    echo "  • Scanning Steam games..."
    while IFS='|' read -r name exe; do
        echo "${name}|Steam|$exe" >> "$index_file"
    done < <(parse_steam_games 2>/dev/null || true)

    # 2. Epic Games
    echo "  • Scanning Epic Games..."
    while IFS='|' read -r name exe; do
        echo "${name}|Epic|$exe" >> "$index_file"
    done < <(parse_epic_games 2>/dev/null || true)

    # 3. Generic user applications
    echo "  • Scanning user applications..."
    local user_dirs=()
    
    # Find Windows user directories dynamically
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
        done < <(find "$MOUNT_POINT/Users" -maxdepth 1 -type d -print0 2>/dev/null || true)
    fi
    
    local check_dirs=(
        "Program Files"
        "Program Files (x86)"
        "${user_dirs[@]}"
    )
    
    for rel_dir in "${check_dirs[@]}"; do
        abs_dir="$MOUNT_POINT/$rel_dir"
        if [[ -d "$abs_dir" ]]; then
            while IFS= read -r -d '' exe; do
                if is_user_app "$exe"; then
                    local basename="$(basename "$exe" .exe)"
                    echo "${basename}|UserApp|$exe" >> "$index_file"
                fi
            done < <(find "$abs_dir" -maxdepth 2 -type f -iname "*.exe" -print0 2>/dev/null || true)
        fi
    done

    # 4. Useful system tools
    echo "  • Scanning system tools..."
    local system_tools=(
        "calc.exe" "notepad.exe" "mspaint.exe" "cmd.exe" "powershell.exe"
        "explorer.exe" "regedit.exe" "taskmgr.exe" "control.exe" "msinfo32.exe"
        "winver.exe" "dxdiag.exe"
    )
    
    for tool in "${system_tools[@]}"; do
        local found="$(find "$MOUNT_POINT/Windows/System32" -type f -iname "$tool" 2>/dev/null | head -n1 || true)"
        if [[ -n "$found" ]]; then
            echo "${tool%.exe}|SystemTool|$found" >> "$index_file"
        fi
    done
    
    echo "Index built with $(wc -l < "$index_file") entries."
}

###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––
###  User Interface Functions
###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––

# Function for fuzzy selection using fzf
fuzzy_select_game() {
    local entries=("$@")
    local display_list=()
    
    for kv in "${entries[@]}"; do
        IFS='|' read -r name exe <<< "$kv"
        local rel_path="${exe#$MOUNT_POINT/}"
        display_list+=("$name  [$rel_path]")
    done

    local chosen
    chosen="$(printf '%s\n' "${display_list[@]}" \
             | fzf --height 60% --reverse --border \
                   --prompt="🎮 Pick a game: " \
                   --header="Use arrows/typing to filter, Enter to select" \
                   --preview-window=hidden)"
    
    [[ -z "$chosen" ]] && return 1

    # Find the corresponding entry
    for i in "${!display_list[@]}"; do
        if [[ "${display_list[i]}" == "$chosen" ]]; then
            printf '%s\n' "${entries[i]}"
            return 0
        fi
    done

    return 1
}

# Function for enhanced search with fzf
enhanced_search() {
    local index_file="$1"
    shift
    local search_term="$*"
    
    [[ ! -f "$index_file" ]] && return 1
    
    local selected
    if [[ -n "$search_term" ]]; then
        # Filter mode: show only matches for the search term
        selected="$(cut -d'|' -f1,2,3 "$index_file" \
                   | fzf --delimiter="|" \
                         --with-nth=1,2 \
                         --prompt="🔍 Search results for '$search_term': " \
                         --query="$search_term" \
                         --height=60% --reverse --border \
                         --header="Filtered results - use arrows/typing to refine" \
                         --preview-window=hidden)"
    else
        # Browse all mode
        selected="$(cut -d'|' -f1,2,3 "$index_file" \
                   | fzf --delimiter="|" \
                         --with-nth=1,2 \
                         --prompt="🔍 Search all apps: " \
                         --height=60% --reverse --border \
                         --header="Type to search, arrows to navigate" \
                         --preview-window=hidden)"
    fi
    
    [[ -z "$selected" ]] && return 1
    
    # Map back to full record
    grep -F "$selected" "$index_file" | head -n1
}

# Fallback numeric selection for systems without fzf
numeric_select_games() {
    local entries=("$@")
    
    echo "🎮 Available Steam Games:"
    echo ""
    
    for i in "${!entries[@]}"; do
        IFS='|' read -r name exe <<< "${entries[i]}"
        local rel_path="${exe#$MOUNT_POINT/}"
        printf "%2d) %-40s [%s]\n" $((i+1)) "$name" "$(dirname "$rel_path")"
    done
    
    echo ""
    read -rp "Select game number (0 to cancel): " choice
    
    if (( choice > 0 && choice <= ${#entries[@]} )); then
        printf '%s\n' "${entries[$((choice-1))]}"
        return 0
    fi
    
    return 1
}

###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––
###  Main Menu Functions
###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––

browse_mode() {
    echo "📋 Browsing installed games and applications..."
    echo ""
    
    # Get Steam games
    mapfile -t steam_games < <(parse_steam_games)
    
    # Get Epic games
    mapfile -t epic_games < <(parse_epic_games)
    
    if [[ ${#steam_games[@]} -eq 0 && ${#epic_games[@]} -eq 0 ]]; then
        echo "No Steam or Epic games detected."
        echo "This might happen if:"
        echo "  • Steam/Epic are not installed on Windows"
        echo "  • Games are installed but metadata is missing"
        echo "  • Fast Startup is preventing proper disk access"
        echo ""
        echo "Try the 'Search' option instead to find applications manually."
        return 1
    fi
    
    # Combine all games
    local all_games=()
    for game in "${steam_games[@]}"; do
        all_games+=("$game")
    done
    for game in "${epic_games[@]}"; do
        all_games+=("$game")
    done
    
    echo "Found ${#steam_games[@]} Steam games and ${#epic_games[@]} Epic games."
    echo ""
    
    local chosen=""
    if command -v fzf &>/dev/null; then
        if chosen="$(fuzzy_select_game "${all_games[@]}")"; then
            IFS='|' read -r name exe <<< "$chosen"
            selected_exe="$exe"
            return 0
        fi
    else
        echo "Note: Install 'fzf' for better search experience."
        echo ""
        if chosen="$(numeric_select_games "${all_games[@]}")"; then
            IFS='|' read -r name exe <<< "$chosen"
            selected_exe="$exe"
            return 0
        fi
    fi
    
    return 1
}

search_mode() {
    echo "🔍 Search for Windows applications"
    echo ""
    
    if [[ ! -f "$index_file" ]]; then
        echo "Building application index first..."
        build_executable_index "$index_file"
        echo ""
    fi
    
    if command -v fzf &>/dev/null; then
        read -rp "Enter search term (or press Enter for full list): " search_term
        echo ""
        
        if result="$(enhanced_search "$index_file" "$search_term")"; then
            IFS='|' read -r name category exe <<< "$result"
            echo "Selected: $name ($category)"
            selected_exe="$exe"
            return 0
        else
            echo "No selection made."
            return 1
        fi
    else
        echo "Enhanced search requires 'fzf'. Install it for the best experience."
        echo "Falling back to basic search..."
        echo ""
        
        read -rp "Enter search term: " search_term
        [[ -z "$search_term" ]] && return 1
        
        echo "Searching for applications matching '$search_term'..."
        
        local matches=()
        while IFS='|' read -r name category exe; do
            if [[ "${name,,}" == *"${search_term,,}"* ]]; then
                matches+=("$name|$category|$exe")
            fi
        done < "$index_file"
        
        if [[ ${#matches[@]} -eq 0 ]]; then
            echo "No matches found for '$search_term'."
            return 1
        fi
        
        echo ""
        echo "Found ${#matches[@]} matches:"
        for i in "${!matches[@]}"; do
            IFS='|' read -r name category exe <<< "${matches[i]}"
            printf "%2d) %-40s [%s]\n" $((i+1)) "$name" "$category"
        done
        
        echo ""
        read -rp "Select number (0 to cancel): " choice
        
        if (( choice > 0 && choice <= ${#matches[@]} )); then
            IFS='|' read -r name category exe <<< "${matches[$((choice-1))]}"
            selected_exe="$exe"
            return 0
        fi
    fi
    
    return 1
}

main_menu() {
    echo ""
    echo "════════════════════════════════════════════"
    echo "🚀 Lin2Win – Windows Application Launcher"
    echo "════════════════════════════════════════════"
    echo ""
    echo "Choose an option:"
    echo "1) 📋 Browse games & applications (Steam, Epic)"
    echo "2) 🔍 Search all executables"
    echo "3) ❌ Exit"
    echo ""
    read -rp "Your choice (1-3): " choice
    echo ""
    
    case "$choice" in
        1) browse_mode ;;
        2) search_mode ;;
        3) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid choice. Please enter 1, 2, or 3." ;;
    esac
}

###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––
###  Main Script Execution
###–––––––––––––––––––––––––––––––––––––––––––––––––––––––––

# Pre-build executable index
index_file="/tmp/lin2win_exe_index.$(date +%s).txt"

# Check if fzf is available
if command -v fzf &>/dev/null; then
    echo "✅ fzf detected - enhanced search experience available"
else
    echo "💡 Tip: Install 'fzf' for better search experience:"
    echo "   • Ubuntu/Debian: sudo apt install fzf"
    echo "   • Fedora: sudo dnf install fzf"
    echo "   • Arch: sudo pacman -S fzf"
fi
echo ""

# Main selection loop
selected_exe=""
while [[ -z "$selected_exe" ]]; do
    main_menu
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

# Cleanup temporary index file
[[ -f "$index_file" ]] && rm -f "$index_file"

# Reboot
echo "Rebooting into Windows to launch: $(basename "$exe")"
sleep 2
sudo reboot
