# Lin2Win PoC

## Overview

Lin2Win allows you to select a Windows executable from Linux, reboot into Windows to launch it automatically, and optionally return to Linux after execution.

## Setup Instructions

### Linux Initial Setup

1. Run the setup script:

   ```bash
   git clone https://github.com/xXJSONDeruloXx/lin2win

   cd lin2win
   
   ./linux/lin2win-setup.sh
   ```

   - The script will auto-detect your Windows partition and boot entry
   - Confirm the detected settings or enter manually if needed


### Windows Initial Setup

1. **Open PowerShell as Administrator** (Right-click Start → "Windows PowerShell (Admin)")

2. **Download and extract the repository:**
   ```powershell
   # Download the repository
   Invoke-WebRequest -Uri "https://github.com/xXJSONDeruloXx/lin2win/archive/refs/heads/main.zip" -OutFile "lin2win.zip"
   
   # Extract the archive
   Expand-Archive -Path "lin2win.zip" -DestinationPath "." -Force
   
   # Navigate to Windows scripts
   cd "lin2win-main\windows"
   ```

3. **Run the setup script:**
   ```powershell
   # Set execution policy to allow scripts
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   
   # Run the Windows setup script
   .\lin2win-setup.ps1
   
   # Optional: Disable Fast Startup for better Linux compatibility
   powercfg /hibernate off
   ```

   **Alternative with Git (if available):**
   ```powershell
   git clone https://github.com/xXJSONDeruloXx/lin2win.git
   cd lin2win\windows
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\lin2win-setup.ps1
   ```

4. **Verify setup:** You should see "Scheduled task 'Lin2WinLauncher' created successfully."

5. **return to Linux:** Once you see the above, you can select reboot from windows menu to go back to linux, where we can now test the direct launch program!

## Linux Launch Test

Once back in your linux partition

1. Launch a Windows executable:

   ```bash
   ./linux/lin2win-launch.sh
   ```

   - Select the desired .exe file from the list.
   - The system will reboot into Windows and launch the selected application.

## Auto-Return Feature

Lin2Win supports automatically returning to Linux when the launched Windows application closes:

### **How It Works**
1. When launching from Linux, you'll be prompted: `Automatically return to Linux when application closes? (y/n)`
2. If you choose "y", Windows will monitor the launched application
3. When the application exits, Windows will restart automatically
4. The system will boot back to its default operating system (Linux)

### **Requirements**
- Linux should be set as the default boot option in your UEFI settings
- Windows must have permission to restart the system

### **Safety Features**
- **One-time use**: Return instruction is consumed and deleted after use
- **Process-specific**: Only monitors the exact application launched from Lin2Win
- **Manual override**: You can manually delete `C:\return_to_linux.txt` to disable auto-return

## Notes

- Ensure that Windows Fast Startup is disabled to allow proper writing to the NTFS partition from Linux.
- The scheduled task runs under the current user context and requires the user to be logged in.
- For automatic return to Linux after application exit, additional scripting is required.

## Troubleshooting

### **"Windows is hibernated" or "unclean file system"**
This is the most common issue. Windows used Fast Startup or hibernation. To fix:

1. **Immediate fix**: Boot into Windows and shutdown properly
   ```bash
   sudo efibootmgr --bootnext 0000  # Use your Windows boot number
   sudo reboot
   ```
   Then in Windows: 
   - Go to Control Panel > Power Options > Choose what the power buttons do
   - Click "Change settings that are currently unavailable"  
   - Uncheck "Turn on fast startup"
   - Restart Windows normally

2. **Quick fix** (may lose unsaved Windows work):
   ```bash
   sudo ntfsfix /dev/nvme0n1p3  # Use your Windows partition
   ```

### **Wrong partition detected**
If no .exe files found, you may have the wrong NTFS partition:
- **Recovery partition** (small, ~768MB) - Contains `$WINRE_BACKUP_PARTITION.MARKER`
- **Main Windows partition** (large, ~930GB) - Contains `Program Files`, `Windows`, `Users`

**Fix**: Re-run setup and choose the larger partition, or manually edit `~/.config/lin2win/config`

### **Manual partition check**
To verify you have the right partition:
```bash
sudo mount -t ntfs-3g /dev/nvme0n1p3 /mnt/windows  # Use your actual partition
ls /mnt/windows/
# Should see: Program Files, Windows, Users, etc.
```

### **Other issues**
- If the executable does not launch, verify the path in C:\launch_on_boot.txt.
- Ensure that the scheduled task is created and enabled in Task Scheduler.
- If PowerShell execution policy errors occur, run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
