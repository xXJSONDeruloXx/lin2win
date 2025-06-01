# Lin2Win PoC

## Overview

Lin2Win allows you to select a Windows executable from Linux, reboot into Windows to launch it automatically, and optionally return to Linux after execution.

## Setup Instructions

### Linux Side

1. Run the setup script:

   ```bash
   ./linux/lin2win-setup.sh
   ```

   - Identify and enter your Windows partition (e.g., sda3).
   - Note the Windows Boot Manager BootNumber (e.g., 0001).

2. Launch a Windows executable:

   ```bash
   ./linux/lin2win-launch.sh
   ```

   - Select the desired .exe file from the list.
   - The system will reboot into Windows and launch the selected application.

### Windows Side

1. Open PowerShell as Administrator.
2. Navigate to the windows directory.
3. Run the setup script:

   ```powershell
   .\lin2win-setup.ps1
   ```

   - This will copy winlauncher.ps1 to C:\ and create a scheduled task to run it at user logon.

## Notes

- Ensure that Windows Fast Startup is disabled to allow proper writing to the NTFS partition from Linux.
- The scheduled task runs under the current user context and requires the user to be logged in.
- For automatic return to Linux after application exit, additional scripting is required.

## Troubleshooting

- If the executable does not launch, verify the path in C:\launch_on_boot.txt.
- Ensure that the scheduled task is created and enabled in Task Scheduler.
