
# Cleanup.ps1
# Run as Administrator.
# Removes kiosk launcher components only.
# Preserves the student account, profile, installed CALIBRATE app, and restrictions.

$ErrorActionPreference = "Continue"

Write-Host "`nStarting Student Kiosk Cleanup..." -ForegroundColor Cyan

# Verify administrator privileges.
$Principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Please run PowerShell as Administrator."
}

# 1. Remove the scheduled task.
$TaskName = "StudentCalibrateLauncher"

$Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($Task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Scheduled task removed." -ForegroundColor Green
}
else {
    Write-Host "Scheduled task not found." -ForegroundColor Yellow
}

# 2. Remove launcher files and logs stored under ProgramData.
$KioskFolder = Join-Path $env:ProgramData "StudentCalibrateKiosk"

if (Test-Path -LiteralPath $KioskFolder) {
    Remove-Item -LiteralPath $KioskFolder -Recurse -Force
    Write-Host "Kiosk launcher files removed." -ForegroundColor Green
}
else {
    Write-Host "Kiosk launcher folder not found." -ForegroundColor Yellow
}

# 3. Remove the temporary installer copy.
# The original installer in the Kiosk folder is preserved.
$InstallerPath = "C:\CALIBRATE-Setup.exe"

if (Test-Path -LiteralPath $InstallerPath) {
    Remove-Item -LiteralPath $InstallerPath -Force
    Write-Host "Temporary installer removed." -ForegroundColor Green
}
else {
    Write-Host "Temporary installer not found." -ForegroundColor Yellow
}

# 4. Deliberately preserve the student account and profile.
Write-Host "Student account and profile preserved." -ForegroundColor Green

# 5. Deliberately preserve installed CALIBRATE and Windows restrictions.
Write-Host "Installed CALIBRATE app and Windows restrictions preserved." -ForegroundColor Green

Write-Host "`nCleanup completed. Restart Windows if needed." -ForegroundColor Cyan
