# winlauncher.ps1: Launch specified executable with optional auto-return

$launchFile = "C:\launch_on_boot.txt"
$returnFile = "C:\return_to_linux.txt"
$targetFile = "C:\lin2win_target.txt"
$logFile = "C:\lin2win_log.txt"

# Function to log messages
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    Write-Host $Message
}

Write-Log "Lin2Win launcher started"

if (Test-Path $launchFile) {
    Write-Log "Launch file found, removing trigger"
    Remove-Item $launchFile
    
    # Get the target executable from persistent file
    if (Test-Path $targetFile) {
        $exePath = Get-Content $targetFile
        Write-Log "Target executable: $exePath"
        
        if (Test-Path $exePath) {
            # Launch the process
            try {
                Start-Process -FilePath $exePath
                Write-Log "Process launched successfully"
            } catch {
                Write-Log "Error launching process: $($_.Exception.Message)"
                exit
            }
            
            # Check if auto-return is requested
            if (Test-Path $returnFile) {
                Write-Log "Auto-return enabled - launcher will stay alive to monitor"
                
                # Extract process name for monitoring
                $processName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
                Write-Log "Will monitor process: $processName"
                
                # Wait a moment for process to start
                Start-Sleep -Seconds 5
                Write-Log "Starting monitoring loop..."
                
                # Monitor until no instances of this process are running
                $loopCount = 0
                do {
                    Start-Sleep -Seconds 2
                    $runningProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
                    $loopCount++
                    
                    # Log every 30 seconds to show we're still monitoring
                    if ($loopCount % 15 -eq 0) {
                        Write-Log "Still monitoring... Found $($runningProcesses.Count) instances of $processName"
                    }
                    
                    # Safety check - if return file is manually deleted, stop monitoring
                    if (-not (Test-Path $returnFile)) {
                        Write-Log "Return file removed manually - stopping monitoring"
                        break
                    }
                    
                } while ($runningProcesses)
                
                # Process has exited or monitoring was cancelled
                if (Test-Path $returnFile) {
                    Write-Log "Process $processName has exited - triggering return to Linux"
                    
                    # Clean up files
                    Remove-Item $returnFile -ErrorAction SilentlyContinue
                    Remove-Item $targetFile -ErrorAction SilentlyContinue
                    
                    Write-Log "Files cleaned up, initiating shutdown in 10 seconds"
                    shutdown /r /t 10 /c "Lin2Win: $processName closed. Returning to Linux in 10 seconds..."
                } else {
                    Write-Log "Monitoring cancelled - cleaning up target file"
                    Remove-Item $targetFile -ErrorAction SilentlyContinue
                }
                
            } else {
                # No auto-return - just launch normally and exit
                Write-Log "No auto-return requested - launcher finishing normally"
                Remove-Item $targetFile -ErrorAction SilentlyContinue
            }
        } else {
            Write-Log "Executable path not found: $exePath"
            # Clean up files if launch fails
            if (Test-Path $returnFile) { Remove-Item $returnFile -ErrorAction SilentlyContinue }
            if (Test-Path $targetFile) { Remove-Item $targetFile -ErrorAction SilentlyContinue }
        }
    } else {
        Write-Log "No target executable file found"
    }
} else {
    Write-Log "No launch instruction found"
}

Write-Log "Lin2Win launcher finished"
