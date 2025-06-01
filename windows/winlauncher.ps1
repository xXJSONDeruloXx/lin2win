# winlauncher.ps1: Launch specified executable on Windows logon

$launchFile = "C:\launch_on_boot.txt"

if (Test-Path $launchFile) {
    $exePath = Get-Content $launchFile
    if (Test-Path $exePath) {
        Start-Process -FilePath $exePath
        Remove-Item $launchFile
    } else {
        Write-Host "Executable path not found: $exePath"
    }
} else {
    Write-Host "No launch instruction found."
}
