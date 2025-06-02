# winlauncher.ps1: Launch specified executable with optional auto-return

$launchFile = "C:\launch_on_boot.txt"
$returnFile = "C:\return_to_linux.txt"
$targetFile = "C:\lin2win_target.txt"

if (Test-Path $launchFile) {
    # Remove launch trigger immediately
    Remove-Item $launchFile
    
    # Get the target executable from persistent file
    if (Test-Path $targetFile) {
        $exePath = Get-Content $targetFile
        
        if (Test-Path $exePath) {
            # Check if auto-return is requested
            if (Test-Path $returnFile) {
                Write-Host "Lin2Win: Launching $exePath with auto-return enabled"
                
                # Launch the process
                Start-Process -FilePath $exePath
                
                # Extract process name for monitoring
                $processName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
                
                # Create background job to monitor process
                Start-Job -ScriptBlock {
                    param($ProcessName, $ReturnFile, $TargetFile)
                    
                    try {
                        # Wait a moment for process to start
                        Start-Sleep -Seconds 3
                        
                        # Monitor until no instances of this process are running
                        do {
                            Start-Sleep -Seconds 2
                            $runningProcesses = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
                        } while ($runningProcesses)
                        
                        # Process has exited - trigger return to Linux
                        if (Test-Path $ReturnFile) {
                            Remove-Item $ReturnFile -ErrorAction SilentlyContinue
                            # Clean up target file after successful return
                            Remove-Item $TargetFile -ErrorAction SilentlyContinue
                            shutdown /r /t 10 /c "Lin2Win: $ProcessName closed. Returning to Linux in 10 seconds..."
                        }
                    } catch {
                        # Clean up on error
                        if (Test-Path $ReturnFile) {
                            Remove-Item $ReturnFile -ErrorAction SilentlyContinue
                        }
                    }
                } -ArgumentList $processName, $returnFile, $targetFile
                
            } else {
                # No auto-return - just launch normally
                Write-Host "Lin2Win: Launching $exePath (no auto-return)"
                Start-Process -FilePath $exePath
                # Clean up target file after launch (no return needed)
                Remove-Item $targetFile -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host "Executable path not found: $exePath"
            # Clean up files if launch fails
            if (Test-Path $returnFile) { Remove-Item $returnFile -ErrorAction SilentlyContinue }
            if (Test-Path $targetFile) { Remove-Item $targetFile -ErrorAction SilentlyContinue }
        }
    } else {
        Write-Host "No target executable specified."
    }
} else {
    Write-Host "No launch instruction found."
}
