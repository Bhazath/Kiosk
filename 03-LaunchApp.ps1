
# 03-LaunchApp.ps1
# Run as Administrator.
# Configures CALIBRATE to launch at student login.
# Deletes the copied installer and signs out only after CALIBRATE
# has successfully started and then exited.

$ErrorActionPreference = "Stop"

$StudentName   = "student"
$InstallerPath = "C:\CALIBRATE-Setup.exe"
$TaskName      = "StudentCalibrateLauncher"
$BasePath      = Join-Path $env:ProgramData "StudentCalibrateKiosk"
$LauncherPath  = Join-Path $BasePath "LaunchApp.ps1"

# Verify administrator privileges.
$Principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Run PowerShell as Administrator."
}

if (-not (Get-LocalUser -Name $StudentName -ErrorAction SilentlyContinue)) {
    throw "Student account does not exist."
}

if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Installer not found: $InstallerPath. Run 02-InstallApp.ps1 first."
}

New-Item -Path $BasePath -ItemType Directory -Force | Out-Null

# This launcher runs in the student session.
$LauncherScript = @'
$ErrorActionPreference = "Stop"

$InstallerPath = "C:\CALIBRATE-Setup.exe"
$LogDirectory  = Join-Path $env:LOCALAPPDATA "StudentCalibrateKiosk"
$LogPath       = Join-Path $LogDirectory "Launcher.log"
$AppPathFile   = Join-Path $LogDirectory "AppPath.txt"
$AppStarted    = $false
$AppExited     = $false

New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $LogPath -Value (
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    )
}

function Find-CalibrateApp {
    $Candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\CALIBRATE\CALIBRATE-PREPROD.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\CALIBRATE\CALIBRATE.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\CALIBRATE-PREPROD.exe"),
        (Join-Path $env:ProgramFiles "CALIBRATE\CALIBRATE-PREPROD.exe"),
        (Join-Path $env:ProgramFiles "CALIBRATE\CALIBRATE.exe")
    )

    if (${env:ProgramFiles(x86)}) {
        $Candidates += @(
            (Join-Path ${env:ProgramFiles(x86)} "CALIBRATE\CALIBRATE-PREPROD.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "CALIBRATE\CALIBRATE.exe")
        )
    }

    if (Test-Path -LiteralPath $AppPathFile) {
        $SavedPath = (Get-Content -LiteralPath $AppPathFile -Raw).Trim()
        if ($SavedPath -and (Test-Path -LiteralPath $SavedPath -PathType Leaf)) {
            return $SavedPath
        }
    }

    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
            return $Candidate
        }
    }

    $SearchRoots = @(
        (Join-Path $env:LOCALAPPDATA "Programs"),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($Root in $SearchRoots) {
        foreach ($Name in @("CALIBRATE-PREPROD.exe", "CALIBRATE.exe")) {
            $Found = Get-ChildItem -LiteralPath $Root -Filter $Name `
                -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($Found) {
                return $Found.FullName
            }
        }
    }

    return $null
}

function Get-CalibrateProcesses {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^CALIBRATE(-PREPROD)?$' }
}

try {
    Write-Log "Launcher started."

    $AppPath = Find-CalibrateApp

    if (-not $AppPath) {
        if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
            throw "CALIBRATE is not installed and the installer is missing."
        }

        Write-Log "CALIBRATE not found. Starting installer."

        # Do not wait indefinitely for an installer that may launch the app.
        $Installer = Start-Process -FilePath $InstallerPath -PassThru
        Write-Log "Installer process started: $($Installer.Id)"

        $InstallDeadline = (Get-Date).AddMinutes(10)

        while ((Get-Date) -lt $InstallDeadline) {
            Start-Sleep -Seconds 3
            $AppPath = Find-CalibrateApp

            if ($AppPath) { break }

            if ($Installer.HasExited) {
                Write-Log "Installer exited with code $($Installer.ExitCode)."
                Start-Sleep -Seconds 5
                $AppPath = Find-CalibrateApp
                if ($AppPath) { break }
            }
        }

        if (-not $AppPath) {
            throw "CALIBRATE executable was not found after installation. Check the installer and log."
        }
    }

    Set-Content -LiteralPath $AppPathFile -Value $AppPath -Force
    Write-Log "Application path: $AppPath"

    # Start a fresh app process and track that exact process.
    $AppProcess = Start-Process -FilePath $AppPath -PassThru
    $AppStarted = $true
    Write-Log "CALIBRATE started. PID: $($AppProcess.Id)"

    $AppProcess.WaitForExit()
    $AppExited = $true
    Write-Log "CALIBRATE exited with code $($AppProcess.ExitCode)."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
}
finally {
    if ($AppStarted -and $AppExited) {
        # Delete the copied installer only after the app has run and exited.
        try {
            if (Test-Path -LiteralPath $InstallerPath -PathType Leaf) {
                Remove-Item -LiteralPath $InstallerPath -Force
                Write-Log "Deleted copied installer."
            }
        }
        catch {
            Write-Log "Installer deletion failed: $($_.Exception.Message)"
        }

        Write-Log "Signing out student after CALIBRATE exit."
        Start-Sleep -Seconds 2
        Start-Process -FilePath "$env:WINDIR\System32\shutdown.exe" `
            -ArgumentList "/l" -WindowStyle Hidden
    }
    else {
        Write-Log "Not signing out: CALIBRATE did not complete a tracked run."
    }
}
'@

Set-Content -LiteralPath $LauncherPath -Value $LauncherScript -Encoding UTF8 -Force

# Run the launcher interactively as the student, without elevation.
$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherPath`""

$Trigger = New-ScheduledTaskTrigger -AtLogOn `
    -User "$env:COMPUTERNAME\$StudentName"

$TaskPrincipal = New-ScheduledTaskPrincipal `
    -UserId "$env:COMPUTERNAME\$StudentName" `
    -LogonType Interactive `
    -RunLevel Limited

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 12)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $TaskPrincipal `
    -Settings $Settings `
    -Description "Launch CALIBRATE at student login." `
    -Force | Out-Null

Write-Host "CALIBRATE launcher task configured." -ForegroundColor Green
Write-Host "Log path when signed in as student:"
Write-Host "$env:LOCALAPPDATA\StudentCalibrateKiosk\Launcher.log"
Write-Host "Sign in as student to test."
