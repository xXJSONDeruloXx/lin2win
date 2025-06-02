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
            # Check if auto-return is requested
            if (Test-Path $returnFile) {
                Write-Log "Auto-return enabled, launching with monitoring"
                
                # Launch the process
                try {
                    Start-Process -FilePath $exePath
                    Write-Log "Process launched successfully"
                } catch {
                    Write-Log "Error launching process: $($_.Exception.Message)"
                }
                
                # Extract process name for monitoring
                $processName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
                Write-Log "Will monitor process: $processName"
                
                # Create background job with enhanced logging
                try {
                    $job = Start-Job -ScriptBlock {
                        param($ProcessName, $ReturnFile, $TargetFile, $LogFile)
                        
                        function Write-JobLog {
                            param($Message)
                            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            "$timestamp - JOB: $Message" | Out-File -FilePath $LogFile -Append
                        }
                        
                        try {
                            Write-JobLog "Background job started for process: $ProcessName"
                            
                            # Wait a moment for process to start
                            Start-Sleep -Seconds 5
                            Write-JobLog "Initial wait completed, starting monitoring loop"
                            
                            # Monitor until no instances of this process are running
                            $loopCount = 0
                            do {
                                Start-Sleep -Seconds 2
                                $runningProcesses = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
                                $loopCount++
                                
                                if ($loopCount % 15 -eq 0) {  # Log every 30 seconds
                                    Write-JobLog "Still monitoring... Found $($runningProcesses.Count) instances of $ProcessName"
                                }
                            } while ($runningProcesses)
                            
                            Write-JobLog "Process $ProcessName has exited, triggering return"
                            
                            # Process has exited - trigger return to Linux
                            if (Test-Path $ReturnFile) {
                                Remove-Item $ReturnFile -ErrorAction SilentlyContinue
                                Remove-Item $TargetFile -ErrorAction SilentlyContinue
                                Write-JobLog "Files cleaned up, initiating shutdown"
                                shutdown /r /t 10 /c "Lin2Win: $ProcessName closed. Returning to Linux in 10 seconds..."
                            } else {
                                Write-JobLog "Return file not found, auto-return cancelled"
                            }
                        } catch {
                            Write-JobLog "Error in background job: $($_.Exception.Message)"
                            # Clean up on error
                            if (Test-Path $ReturnFile) {
                                Remove-Item $ReturnFile -ErrorAction SilentlyContinue
                            }
                        }
                    } -ArgumentList $processName, $returnFile, $targetFile, $logFile
                    
                    Write-Log "Background job created with ID: $($job.Id)"
                } catch {
                    Write-Log "Error creating background job: $($_.Exception.Message)"
                }
                
            } else {
                # No auto-return - just launch normally
                Write-Log "No auto-return requested, launching normally"
                try {
                    Start-Process -FilePath $exePath
                    Remove-Item $targetFile -ErrorAction SilentlyContinue
                    Write-Log "Process launched, target file cleaned up"
                } catch {
                    Write-Log "Error launching process: $($_.Exception.Message)"
                }
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
