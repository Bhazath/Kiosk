# 03-LaunchApp.ps1
# Run as Administrator.
# Installs CALIBRATE only when missing, launches it at student login,
# deletes C:\CALIBRATE-Setup.exe after CALIBRATE exits, then signs out.

$ErrorActionPreference = "Stop"

$StudentName  = "student"
$InstallerPath = "C:\CALIBRATE-Setup.exe"
$TaskName      = "StudentCalibrateLauncher"
$BasePath      = Join-Path $env:ProgramData "StudentCalibrateKiosk"
$LauncherPath  = Join-Path $BasePath "LaunchApp.ps1"

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
    throw "Installer not found: $InstallerPath"
}

New-Item -Path $BasePath -ItemType Directory -Force | Out-Null

$LauncherScript = @'
$ErrorActionPreference = "Stop"

$InstallerPath = "C:\CALIBRATE-Setup.exe"
$LogDirectory = Join-Path $env:LOCALAPPDATA "StudentCalibrateKiosk"
$LogPath = Join-Path $LogDirectory "Launcher.log"
$AppPathFile = Join-Path $LogDirectory "AppPath.txt"
$AppStarted = $false

New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
}

function Find-CalibrateApp {
    $Candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\CALIBRATE\CALIBRATE-PREPROD.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\CALIBRATE\CALIBRATE.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\CALIBRATE-PREPROD.exe"),
        (Join-Path $env:ProgramFiles "CALIBRATE\CALIBRATE-PREPROD.exe"),
        (Join-Path $env:ProgramFiles "CALIBRATE\CALIBRATE.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "CALIBRATE\CALIBRATE-PREPROD.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "CALIBRATE\CALIBRATE.exe")
    )

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
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^CALIBRATE(-PREPROD)?\.exe$' }
}

try {
    Write-Log "Launcher started."

    $AppPath = Find-CalibrateApp

    if (-not $AppPath) {
        Write-Log "CALIBRATE not found. Starting installer."

        if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
            throw "Installer not found: $InstallerPath"
        }

        $Installer = Start-Process -FilePath $InstallerPath -PassThru -Wait
        Write-Log "Installer exited with code $($Installer.ExitCode)."

        Start-Sleep -Seconds 5
        $AppPath = Find-CalibrateApp

        if (-not $AppPath) {
            throw "Installer finished, but CALIBRATE executable was not found."
        }
    }

    Set-Content -LiteralPath $AppPathFile -Value $AppPath -Force
    Write-Log "Application path: $AppPath"

    # The installer may launch the application itself.
    $Existing = Get-CalibrateProcesses | Select-Object -First 1

    if ($Existing) {
        $AppProcess = Get-Process -Id $Existing.ProcessId -ErrorAction SilentlyContinue
        Write-Log "CALIBRATE is already running."
    }
    else {
        $AppProcess = Start-Process -FilePath $AppPath -PassThru
        Write-Log "CALIBRATE launched."
    }

    if ($AppProcess) {
        $AppStarted = $true
        $AppProcess.WaitForExit()
        Write-Log "CALIBRATE exited."
    }
    else {
        # Handle the application restarting during startup.
        $Deadline = (Get-Date).AddMinutes(2)
        $Running = $null

        while ((Get-Date) -lt $Deadline) {
            Start-Sleep -Seconds 2
            $Running = Get-CalibrateProcesses | Select-Object -First 1
            if ($Running) { break }
        }

        if (-not $Running) {
            throw "CALIBRATE did not start."
        }

        $AppStarted = $true
        $ProcessId = $Running.ProcessId
        Write-Log "Waiting for CALIBRATE process $ProcessId."

        while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 2
        }

        Write-Log "CALIBRATE exited."
    }
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
}
finally {
    if ($AppStarted) {
        # Delete the copied installer only after CALIBRATE has exited.
        try {
            if (Test-Path -LiteralPath $InstallerPath -PathType Leaf) {
                Remove-Item -LiteralPath $InstallerPath -Force -ErrorAction Stop
                Write-Log "Deleted installer: $InstallerPath"
            }
        }
        catch {
            Write-Log "Could not delete installer: $($_.Exception.Message)"
        }
    }

    Write-Log "Signing out student."
    Start-Sleep -Seconds 2
    Start-Process -FilePath "$env:WINDIR\System32\shutdown.exe" `
        -ArgumentList "/l" -WindowStyle Hidden
}
'@

Set-Content -LiteralPath $LauncherPath -Value $LauncherScript -Encoding UTF8 -Force

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherPath`""

$Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:COMPUTERNAME\$StudentName"

$TaskPrincipal = New-ScheduledTaskPrincipal `
    -UserId "$env:COMPUTERNAME\$StudentName" `
    -LogonType Interactive `
    -RunLevel Limited

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $TaskPrincipal `
    -Settings $Settings `
    -Description "Launch CALIBRATE at student login and sign out when it exits." `
    -Force | Out-Null

Write-Host "CALIBRATE launcher task configured." -ForegroundColor Green
Write-Host "The installer will be deleted from C:\ after CALIBRATE exits."
Write-Host "Sign in as student to test."