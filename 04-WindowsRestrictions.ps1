
# 04-WindowsRestrictions.ps1
# Run as Administrator while signed in to the admin account.
# Signs out the student session, unloads the profile, and applies restrictions.

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Student Windows Restrictions" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Check administrator privileges
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Run this script as Administrator."
}

# 2. Verify the student account
$Student = "student"
$Account = Get-LocalUser -Name $Student -ErrorAction SilentlyContinue

if (-not $Account) {
    throw "Student account not found. Run 01-CreateStudent.ps1 first."
}

$Sid = $Account.SID.Value

# 3. Sign out active student sessions only
Write-Host "Checking for active student sessions..." -ForegroundColor Yellow

$QuserOutput = quser 2>$null

if ($LASTEXITCODE -eq 0 -and $QuserOutput) {
    foreach ($Line in ($QuserOutput | Select-Object -Skip 1)) {
        # Handles the optional leading > used for the current session.
        if ($Line -match '^\s*>?\s*(\S+)\s+(\S+)?\s*(\d+)\s+') {
            $SessionUser = $Matches[1]
            $SessionId = [int]$Matches[3]

            if ($SessionUser -ieq $Student) {
                Write-Host "Signing out student session ID $SessionId..." -ForegroundColor Yellow
                & logoff.exe $SessionId

                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Could not sign out session $SessionId. Windows may still be closing it."
                }
            }
        }
    }
}

# 4. Wait for Windows to unload the student profile
Write-Host "Waiting for student profile to unload..." -ForegroundColor Yellow

$Deadline = (Get-Date).AddSeconds(45)

do {
    Start-Sleep -Seconds 2

    $LoadedProfile = Get-CimInstance Win32_UserProfile |
        Where-Object { $_.SID -eq $Sid -and $_.Loaded }

} while ($LoadedProfile -and (Get-Date) -lt $Deadline)

if ($LoadedProfile) {
    throw "Student profile remains loaded. Check for disconnected student sessions and retry."
}

# 5. Find the student profile
$Profile = Get-CimInstance Win32_UserProfile |
    Where-Object { $_.SID -eq $Sid }

if (-not $Profile) {
    throw "Student profile not found. Sign in as student once, sign out, and rerun."
}

$ProfilePath = $Profile.LocalPath
$NtUserDat = Join-Path $ProfilePath "NTUSER.DAT"

if (-not (Test-Path $NtUserDat)) {
    throw "Student NTUSER.DAT not found at '$NtUserDat'."
}

# 6. Load the student registry hive
$Hive = "StudentRestrictionsTemp"
$Root = "Registry::HKEY_USERS\$Hive"

if (Test-Path $Root) {
    throw "Temporary registry hive HKU\$Hive already exists. Restart Windows and retry."
}

Write-Host "Loading student registry..." -ForegroundColor Yellow

& reg.exe load "HKU\$Hive" "$NtUserDat"

if ($LASTEXITCODE -ne 0) {
    throw "Could not load student registry. Check whether another process has locked NTUSER.DAT."
}

try {
    # 7. Explorer and Start menu restrictions
    $Explorer = "$Root\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    New-Item -Path $Explorer -Force | Out-Null

    $ExplorerSettings = @{
        NoRun                      = 1
        NoFind                     = 1
        NoControlPanel             = 1
        NoViewContextMenu          = 1
        NoTrayContextMenu          = 1
        NoSetTaskbar               = 1
        NoChangeStartMenu          = 1
        NoStartMenuPinnedList      = 1
        NoStartMenuMFUprogramsList = 1
        NoStartMenuSubFolders      = 1
        NoWinKeys                  = 1
        NoViewOnDrive              = 67108863
        NoDrives                   = 67108863
        NoDesktop                  = 1
    }

    foreach ($Entry in $ExplorerSettings.GetEnumerator()) {
        New-ItemProperty -Path $Explorer `
            -Name $Entry.Key `
            -Value $Entry.Value `
            -PropertyType DWord `
            -Force | Out-Null
    }

    # Hide all Windows Settings pages
    New-ItemProperty -Path $Explorer `
        -Name "SettingsPageVisibility" `
        -Value "hide:*" `
        -PropertyType String `
        -Force | Out-Null

    # 8. System restrictions — Task Manager intentionally NOT blocked
    $System = "$Root\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    New-Item -Path $System -Force | Out-Null

    $SystemSettings = @{
        NoDispCPL            = 1
        NoDispBackgroundPage = 1
        NoDispAppearancePage = 1
        NoDispScrSavPage     = 1
        DisableRegistryTools = 1
    }

    foreach ($Entry in $SystemSettings.GetEnumerator()) {
        New-ItemProperty -Path $System `
            -Name $Entry.Key `
            -Value $Entry.Value `
            -PropertyType DWord `
            -Force | Out-Null
    }

    # 9. Disable Command Prompt for student
    $CommandProcessor = "$Root\Software\Policies\Microsoft\Windows\System"
    New-Item -Path $CommandProcessor -Force | Out-Null

    New-ItemProperty -Path $CommandProcessor `
        -Name "DisableCMD" `
        -Value 2 `
        -PropertyType DWord `
        -Force | Out-Null

    # 10. Disable Windows Installer for student
    $InstallerPolicy = "$Root\Software\Policies\Microsoft\Windows\Installer"
    New-Item -Path $InstallerPolicy -Force | Out-Null

    New-ItemProperty -Path $InstallerPolicy `
        -Name "DisableMSI" `
        -Value 2 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Host "Explorer restrictions applied." -ForegroundColor Green
    Write-Host "Settings restrictions applied." -ForegroundColor Green
    Write-Host "Command Prompt restriction applied." -ForegroundColor Green
    Write-Host "Task Manager remains enabled." -ForegroundColor Green
}
finally {
    # 11. Unload the temporary registry hive
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    & reg.exe unload "HKU\$Hive"

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not unload the registry hive. Restart Windows before testing."
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Restrictions configured" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Sign in as student again to test the changes."
Write-Host "These policies restrict common Windows interfaces, not every possible way to launch programs."
