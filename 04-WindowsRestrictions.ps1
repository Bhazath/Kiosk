# 04-WindowsRestrictions.ps1
# Run as Administrator
# This version automatically creates the student profile if it doesn't exist

$ErrorActionPreference = "Stop"

$studentUser   = "student"
$studentPass   = "student"
$calibrateExe  = "C:\Users\student\AppData\Local\Programs\CALIBRATE\CALIBRATE-PREPROD.exe"
$hiveName      = "StudentRestrictionsTemp"
$hivePath      = "HKU\$hiveName"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Windows Restrictions for Student User" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ---------- Force create student profile if missing ----------
$studentProfileInfo = Get-CimInstance Win32_UserProfile |
    Where-Object { $_.LocalPath -like "*\$studentUser" -and -not $_.Special }

if (-not $studentProfileInfo -or -not (Test-Path "C:\Users\$studentUser\NTUSER.DAT")) {
    Write-Host "Student profile not found. Creating it automatically..." -ForegroundColor Yellow

    $securePass = ConvertTo-SecureString $studentPass -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ("$env:COMPUTERNAME\$studentUser", $securePass)

    # This forces Windows to create the full user profile
    $proc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c echo ProfileCreated" `
        -Credential $cred `
        -LoadUserProfile `
        -Wait `
        -WindowStyle Hidden `
        -PassThru `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 3

    # Refresh profile info
    $studentProfileInfo = Get-CimInstance Win32_UserProfile |
        Where-Object { $_.LocalPath -like "*\$studentUser" -and -not $_.Special }
}

if (-not $studentProfileInfo) {
    throw "Failed to create student profile. Please login as student once manually."
}

$studentProfile = $studentProfileInfo.LocalPath
$ntUserDat = Join-Path $studentProfile "NTUSER.DAT"

Write-Host "Student profile: $studentProfile" -ForegroundColor Green

if (-not (Test-Path $ntUserDat)) {
    throw "NTUSER.DAT still missing after profile creation attempt."
}

if ($studentProfileInfo.Loaded) {
    throw "Student profile is currently loaded. Sign out of student and try again."
}

# ---------- Load hive ----------
Write-Host "Loading student registry hive..." -ForegroundColor Yellow
$result = & reg.exe load $hivePath $ntUserDat 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Failed to load hive: $result"
}

try {
    $explorerPolicy = "$hivePath\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $systemPolicy   = "$hivePath\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    $winlogonKey    = "$hivePath\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $advancedKey    = "$hivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $searchKey      = "$hivePath\Software\Microsoft\Windows\CurrentVersion\Search"

    foreach ($key in @($explorerPolicy, $systemPolicy, $winlogonKey, $advancedKey, $searchKey)) {
        & reg.exe add $key /f | Out-Null
    }

    Write-Host "Applying restrictions..." -ForegroundColor Yellow

    # Explorer restrictions
    $explorerSettings = @{
        NoDesktop                  = 1
        NoRun                      = 1
        NoFind                     = 1
        NoClose                    = 1
        NoSetTaskbar               = 1
        NoTrayItemsDisplay         = 1
        NoWinKeys                  = 1
        NoTaskSwitches             = 1
        NoViewContextMenu          = 1
        NoLogoff                   = 1
        NoChangeStartMenu          = 1
        HideClock                  = 1
        NoStartMenuSubFolders      = 1
        NoStartMenuPinnedList      = 1
        NoStartMenuMFUprogramsList = 1
        NoControlPanel             = 1
    }

    foreach ($item in $explorerSettings.GetEnumerator()) {
        & reg.exe add $explorerPolicy /v $item.Key /t REG_DWORD /d $item.Value /f | Out-Null
    }

    # System
    & reg.exe add $systemPolicy /v NoControlPanel /t REG_DWORD /d 1 /f | Out-Null
    & reg.exe add $systemPolicy /v DisableTaskMgr /t REG_DWORD /d 1 /f | Out-Null

    # Taskbar buttons
    $advancedSettings = @{
        ShowTaskViewButton = 0
        TaskbarDa          = 0
        TaskbarMn          = 0
        TaskbarSearch      = 0
    }

    foreach ($item in $advancedSettings.GetEnumerator()) {
        & reg.exe add $advancedKey /v $item.Key /t REG_DWORD /d $item.Value /f | Out-Null
    }

    # Search
    & reg.exe add $searchKey /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f | Out-Null
    & reg.exe add $searchKey /v BingSearchEnabled /t REG_DWORD /d 0 /f | Out-Null
    & reg.exe add $searchKey /v CortanaConsent /t REG_DWORD /d 0 /f | Out-Null

    # Force Shell
    if (Test-Path $calibrateExe) {
        & reg.exe add $winlogonKey /v Shell /t REG_SZ /d "`"$calibrateExe`"" /f | Out-Null
        Write-Host "Shell set to CALIBRATE app" -ForegroundColor Green
    }
    else {
        Write-Warning "CALIBRATE.exe not found yet. Shell will be set later when app is installed."
    }

    Write-Host "All restrictions applied" -ForegroundColor Green
}
finally {
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 1
    & reg.exe unload $hivePath | Out-Null
    Write-Host "Hive unloaded" -ForegroundColor Green
}

# Startup shortcut (backup)
$startupFolder = Join-Path $studentProfile "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
New-Item -Path $startupFolder -ItemType Directory -Force | Out-Null

if (Test-Path $calibrateExe) {
    $shortcutPath = Join-Path $startupFolder "CALIBRATE.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $calibrateExe
    $shortcut.WorkingDirectory = Split-Path $calibrateExe
    $shortcut.Save()
    Write-Host "Startup shortcut created" -ForegroundColor Green
}

Write-Host ""
Write-Host "COMPLETED SUCCESSFULLY" -ForegroundColor Green
Write-Host "You can now restart and login as student."