# winlauncher.ps1: Launch specified executable on Windows logon with optional auto-return

$launchFile = "C:\launch_on_boot.txt"
$returnFile = "C:\return_to_linux.txt"

if (Test-Path $launchFile) {
    $exePath = Get-Content $launchFile
    Remove-Item $launchFile  # Clean up launch instruction immediately
    
    if (Test-Path $exePath) {
        # Check if auto-return is requested
        if (Test-Path $returnFile) {
            Write-Host "Lin2Win: Launching $exePath with auto-return enabled"
            
            # Launch the process and get the process object for monitoring
            $process = Start-Process -FilePath $exePath -PassThru
            
            # Create background job to monitor process and handle return
            Start-Job -ScriptBlock {
                param($ProcessId, $ReturnFile)
                
                try {
                    # Wait for the specific process to exit
                    Wait-Process -Id $ProcessId -ErrorAction SilentlyContinue
                    
                    # Check if return file still exists (safety check)
                    if (Test-Path $ReturnFile) {
                        Remove-Item $ReturnFile -ErrorAction SilentlyContinue
                        
                        # Simple restart - will boot to default (Linux)
                        shutdown /r /t 10 /c "Lin2Win: Returning to Linux in 10 seconds..."
                    }
                } catch {
                    # Clean up return file if something goes wrong
                    if (Test-Path $ReturnFile) {
                        Remove-Item $ReturnFile -ErrorAction SilentlyContinue
                    }
                }
            } -ArgumentList $process.Id, $returnFile
            
        } else {
            # No auto-return - just launch normally
            Write-Host "Lin2Win: Launching $exePath (no auto-return)"
            Start-Process -FilePath $exePath
        }
    } else {
        Write-Host "Executable path not found: $exePath"
        # Clean up return file if launch fails
        if (Test-Path $returnFile) {
            Remove-Item $returnFile -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "No launch instruction found."
}
