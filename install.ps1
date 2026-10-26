<# 
.SYNOPSIS
    Install btm-custom to system PATH, create shortcuts and default config
#>

param(
    [string]$BinaryPath = "C:\Users\CPXru\Desktop\thumb\bottom\target\release\btm.exe",
    [string]$InstallDir = "$env:USERPROFILE\.local\bin",
    [switch]$CreateShortcut,
    [switch]$AddToPath
)

Write-Host "=== btm-custom Installer ===" -ForegroundColor Cyan

if (-not (Test-Path $BinaryPath)) {
    Write-Error "Binary not found at $BinaryPath"
    exit 1
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "Created directory: $InstallDir"
}

$DestPath = Join-Path $InstallDir "btm.exe"
Copy-Item -Path $BinaryPath -Destination $DestPath -Force
Write-Host "Copied to: $DestPath"

if ($AddToPath -or $CreateShortcut) {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($UserPath -notlike "*$InstallDir*") {
        $NewPath = "$UserPath;$InstallDir"
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        Write-Host "Added to User PATH: $InstallDir" -ForegroundColor Green
        Write-Warning "Restart terminal or re-login to take effect"
    }
}

if ($CreateShortcut) {
    try {
        $DesktopPath = [Environment]::GetFolderPath("Desktop")
        $ShortcutPath = Join-Path $DesktopPath "btm.lnk"
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = $DestPath
        $Shortcut.Arguments = "--disable_gpu=false"
        $Shortcut.WorkingDirectory = $InstallDir
        $Shortcut.IconLocation = $DestPath
        $Shortcut.Description = "btm-custom system monitor with GPU"
        $Shortcut.Save()
        Write-Host "Created desktop shortcut: $ShortcutPath"
    } catch {
        Write-Warning "Failed to create desktop shortcut: $($_.Exception.Message)"
    }
}

$ConfigDir = Join-Path $env:APPDATA "bottom"
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}
$ConfigFile = Join-Path $ConfigDir "bottom.toml"
if (-not (Test-Path $ConfigFile)) {
    @"
# btm-custom config
[flags]
disable_gpu = false

[recording]
enabled = true
interval = "5s"
output_dir = "C:\\Users\\$env:USERNAME\\.local\\share\\bottom\\logs"
keep_days = 30
compress = true

basic = false
rate = 1000
retention = "600s"
"@ | Out-File -Encoding utf8 $ConfigFile
    Write-Host "Created default config: $ConfigFile"
}

Write-Host "`nInstall complete!" -ForegroundColor Green
Write-Host "Usage:"
Write-Host "  btm                    # Live monitor"
Write-Host "  btm --record           # Background record"
Write-Host "  btm --basic            # Lightweight mode"
Write-Host "  btm --disable_gpu=false  # Force GPU"