$ErrorActionPreference = "Stop"
trap { Write-Output "ERROR: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; exit 1 }

# CONFIG ================
# Required. Red Giant needs the Maxon App and WebView2 Runtime alongside it.
$RED_GIANT_S3_URI = "s3://<bucket>/RedGiant-2026.0.0-Win.exe"  # required. e.g. s3://<bucket>/RedGiant-2026.0.0-Win.exe
$MAXON_APP_S3_URI = "s3://<bucket>/Maxon_App_2026.0.0_Win.exe"  # required. e.g. s3://<bucket>/Maxon_App_2026.0.0_Win.exe
$WEBVIEW2_S3_URI  = "s3://<bucket>/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"  # required. e.g. s3://<bucket>/MicrosoftEdgeWebView2RuntimeInstallerX64.exe
# END CONFIG ================

function Initialize-Junctions {
    param([bool]$CreateTargets)
    foreach ($j in $junctions) {
        if (Test-Path $j.Link) {
            $item = Get-Item $j.Link -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            Remove-Item $j.Link -Recurse -Force
        }
        $parent = Split-Path $j.Link -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        if ($CreateTargets) { New-Item -ItemType Directory -Path $j.Target -Force | Out-Null }
        New-Item -ItemType Junction -Path $j.Link -Target $j.Target
        Write-Host "Junction: $($j.Link) -> $($j.Target)"
    }
}

function Export-InstallerState {
    New-Item -ItemType Directory -Path $SVC_BACKUP -Force | Out-Null
    $services = Get-WmiObject Win32_Service | Where-Object {
        $_.PathName -like "*Red Giant*" -or $_.Name -like "*RedGiant*"
    }
    foreach ($svc in $services) {
        @{ Name = $svc.Name; DisplayName = $svc.DisplayName; PathName = $svc.PathName
           StartMode = $svc.StartMode; Description = $svc.Description
        } | ConvertTo-Json | Out-File "$SVC_BACKUP\$($svc.Name).json"
    }
}

function Import-InstallerState {
    if (Test-Path $SVC_BACKUP) {
        foreach ($file in Get-ChildItem "$SVC_BACKUP\*.json") {
            try {
                $svcInfo = Get-Content $file.FullName | ConvertFrom-Json
                if ($svcInfo.Name -notlike "*Red Giant*" -and $svcInfo.Name -notlike "*RedGiant*") { continue }
                $existing = Get-Service -Name $svcInfo.Name -ErrorAction SilentlyContinue
                if (-not $existing) {
                    $startType = switch ($svcInfo.StartMode) { "Auto" { "auto" } "Manual" { "demand" } "Disabled" { "disabled" } default { "auto" } }
                    sc.exe create $svcInfo.Name binPath= "$($svcInfo.PathName)" start= $startType DisplayName= "$($svcInfo.DisplayName)"
                    if ($svcInfo.Description) { sc.exe description $svcInfo.Name "$($svcInfo.Description)" }
                    Write-Host "Registered service: $($svcInfo.Name)"
                }
                if ($svcInfo.StartMode -eq "Auto") {
                    Start-Service -Name $svcInfo.Name -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Host "WARNING: Failed to restore service $($file.Name): $_"
            }
        }
    }
}

function Invoke-WithErrorCapture($path, $argList){
    $outFile = New-TemporaryFile
    $errFile = New-TemporaryFile
    $p = Start-Process -FilePath $path -ArgumentList $argList -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outFile.FullName -RedirectStandardError $errFile.FullName
    if ($p.ExitCode -ne 0) {
        throw "Command failed with exit code $($p.ExitCode): $path $argList`n$(Get-Content $outFile -Raw)$(Get-Content $errFile -Raw)"
    }
}
function Save-URI($uri){
    $file = Split-Path -Leaf $uri
    $path = "$DOWNLOADS_PATH\$file"
    $outFile = New-TemporaryFile
    $errFile = New-TemporaryFile
    $p = Start-Process -FilePath "aws" -ArgumentList "s3 cp --no-progress `"$uri`" `"$path`"" -PassThru -NoNewWindow -RedirectStandardOutput $outFile.FullName -RedirectStandardError $errFile.FullName
    $p.Handle | Out-Null
    return [pscustomobject]@{ FilePath = $path; File = $file; ErrFile = $errFile.FullName; OutFile = $outFile.FullName; Uri = $uri; Process = $p }
}
function Wait-Download($download){
    $download.Process.WaitForExit()
    if ($download.Process.ExitCode -ne 0 -or -not (Test-Path $download.FilePath)) { throw "Download failed ($($download.Process.ExitCode)): $($download.Uri)`n$(Get-Content $download.OutFile -Raw)$(Get-Content $download.ErrFile -Raw)" }
}
function Write-Duration($start, $name){ Write-Host "$($name): $(((Get-Date) - $start).ToString('hh\:mm\:ss'))" }

$MOUNT_PATH = [Environment]::GetEnvironmentVariable("DEADLINE_PERSISTENT_MOUNT", "Machine")
if (-not $MOUNT_PATH) {
    Write-Host "No persistent volume - normal install"
    $PERSISTENCE_ENABLED = $false
} else {
    Write-Host "Persistent volume detected at: $MOUNT_PATH"
    $PERSISTENCE_ENABLED = $true
    $SW_PATH = "$MOUNT_PATH\Software"
    $DATA_PATH = "$MOUNT_PATH\SoftwareData"
    $SVC_BACKUP = "$MOUNT_PATH\SoftwareServices"
    $INSTALL_MARKER = "$SW_PATH\.install-complete"
}

# All three components are required, so their junctions are always created when persistence is on.
$junctions = @()
if ($PERSISTENCE_ENABLED) {
    $junctions = @(
        @{ Link = "C:\Program Files\Maxon"; Target = "$SW_PATH\Maxon" }
        @{ Link = "C:\Program Files\Red Giant"; Target = "$SW_PATH\Red Giant" }
        @{ Link = "C:\Program Files (x86)\Microsoft\EdgeWebView"; Target = "$SW_PATH\EdgeWebView" }
        @{ Link = "C:\ProgramData\Maxon"; Target = "$DATA_PATH\Maxon" }
        @{ Link = "C:\ProgramData\Red Giant"; Target = "$DATA_PATH\Red Giant" }
    )
}

$scriptStartTime = Get-Date

if ($PERSISTENCE_ENABLED -and (Test-Path $INSTALL_MARKER)) {
    Write-Host "=== Restoring from persistent volume ==="
    $restoreStart = Get-Date
    Initialize-Junctions -CreateTargets $false
    Import-InstallerState
    Write-Duration $restoreStart "Restore"
    Write-Duration $scriptStartTime "Total"
    exit 0
}

if ($PERSISTENCE_ENABLED) {
    Write-Host "=== First boot - installing to persistent volume ==="
    Initialize-Junctions -CreateTargets $true
}

$DOWNLOADS_PATH = "C:\Temp"

if (-not $RED_GIANT_S3_URI) { throw "CONFIG RED_GIANT_S3_URI is required" }
if (-not $MAXON_APP_S3_URI) { throw "CONFIG MAXON_APP_S3_URI is required" }
if (-not $WEBVIEW2_S3_URI) { throw "CONFIG WEBVIEW2_S3_URI is required" }

Write-Host "Downloading installers from S3 (parallel)..."
$webview2Download = Save-URI $WEBVIEW2_S3_URI
$maxonDownload = Save-URI $MAXON_APP_S3_URI
$rgDownload = Save-URI $RED_GIANT_S3_URI

$webview2StartTime = Get-Date
Write-Host "Installing Microsoft Edge WebView2 Runtime..."
Wait-Download $webview2Download
Invoke-WithErrorCapture $webview2Download.FilePath @("/silent", "/install")
Write-Duration $webview2StartTime "WebView2"

$maxonStartTime = Get-Date
Write-Host "Installing Maxon App..."
Wait-Download $maxonDownload
Invoke-WithErrorCapture $maxonDownload.FilePath @("--mode", "unattended", "--unattendedmodeui", "none")
Write-Duration $maxonStartTime "Maxon"

$rgStartTime = Get-Date
Write-Host "Installing Red Giant..."
Wait-Download $rgDownload
Invoke-WithErrorCapture $rgDownload.FilePath @("--mode", "unattended", "--unattendedmodeui", "none")
Write-Duration $rgStartTime "Red Giant"

if ($PERSISTENCE_ENABLED) {
    Export-InstallerState
    Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Out-File $INSTALL_MARKER
    Write-Host "Install marker written"
}

Write-Duration $scriptStartTime "Total"
Write-Host "All installations completed!"
