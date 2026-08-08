$ErrorActionPreference = "Stop"
trap { Write-Output "ERROR: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; exit 1 }

# CONFIG ================
# Required
$MAX_VERSION = "2027"  # required. format: YYYY. supported: 2024, 2025, 2026, 2027
# Installer zip: https://github.com/aws-deadline/deadline-cloud-samples/blob/mainline/host_configuration_scripts/3dsmax/README.md
$3DS_MAX_INSTALLER_ZIP_S3_URI = "s3://<bucket>/3ds-max-2027.zip"  # required

# Optional components. Leave blank to skip.
$VRAY_S3_URI = ""            # e.g. s3://<bucket>/vray_adv_max2027.exe
$TYFLOW_S3_URI = ""          # .dlo for MAX_VERSION. e.g. s3://<bucket>/tyFlow_2027.dlo
$FOREST_PACK_S3_URI = ""     # e.g. s3://<bucket>/ForestPackPro_x64.exe
$RAILCLONE_S3_URI = ""       # e.g. s3://<bucket>/RailClonePro.exe
$FLOORGENERATOR_S3_URI = ""  # .dlm for MAX_VERSION. e.g. s3://<bucket>/FloorGenerator_max2027.dlm
$MULTITEXTURE_S3_URI = ""    # .dlt for MAX_VERSION. e.g. s3://<bucket>/MultiTexture_max2027.dlt

# 2027 render nodes need ADP consent to start, and it enables Autodesk analytics. See the README.
$ADP_ANALYTICS_OPT_IN = $false  # $true or $false. 2027 only
# END CONFIG ================

$MAX_ROOT = "C:\Program Files\Autodesk\3ds Max $MAX_VERSION"
$MAX_PY = "$MAX_ROOT\Python"
$PLUGINS_DIR = "$MAX_ROOT\plugins"
$VRAY_ROOT = "C:\Program Files\Chaos\V-Ray\3ds Max $MAX_VERSION"
$VRAY_PLUGIN = "C:\ProgramData\Autodesk\ApplicationPlugins\VRay3dsMax$MAX_VERSION"
$ITOO_ROOT = "C:\Program Files\Itoo Software"
$DOWNLOADS_PATH = "C:\Temp"
$SETUP_PATH = "C:\3dsmax_setup"
# Product registration only, no licensing state. See the README
$REG_KEYS = @("HKLM\SOFTWARE\Autodesk\3dsMax", "HKLM\SOFTWARE\Chaos Group", "HKLM\SOFTWARE\Itoo Software")

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
function Set-MachineEnvVar($name, $value){ [Environment]::SetEnvironmentVariable($name,$value,"Machine") }
function Write-Duration($start, $name){ Write-Host "$($name): $(((Get-Date) - $start).ToString('hh\:mm\:ss'))" }

# Env vars are on the OS disk, so re-set them on every boot
function Set-AllEnvVars {
    Set-MachineEnvVar "Path" "$MAX_ROOT;$MAX_PY;$MAX_PY\Scripts;$([Environment]::GetEnvironmentVariable('Path','Machine'))"
    Set-MachineEnvVar "3DSMAX_EXECUTABLE" "$MAX_ROOT\3dsmaxbatch.exe"
    Set-MachineEnvVar "PYTHONPATH" "$MAX_PY;$MAX_PY\Scripts"
    if ($VRAY_S3_URI) {
        Set-MachineEnvVar "VRAY_FOR_3DSMAX${MAX_VERSION}_MAIN" "$VRAY_PLUGIN\bin\"
        Set-MachineEnvVar "VRAY_FOR_3DSMAX${MAX_VERSION}_PLUGINS" "$VRAY_PLUGIN\bin\plugins\"
        Set-MachineEnvVar "VRAY_MDL_PATH_3DSMAX$MAX_VERSION" "$VRAY_ROOT\mdl"
    }
    foreach ($p in @(@{ Uri = $FOREST_PACK_S3_URI; Var = "FOREST_PACK_PRO"; Dir = "Forest Pack Pro" },
                     @{ Uri = $RAILCLONE_S3_URI; Var = "RAILCLONE_PRO"; Dir = "RailClone Pro" })) {
        if (-not $p.Uri) { continue }
        Set-MachineEnvVar "ITOO_SOFTWARE_$($p.Var)_MAINDIR" "$ITOO_ROOT\$($p.Dir)"
        Set-MachineEnvVar "ITOO_SOFTWARE_$($p.Var)_USELICSERVER" "0"
    }
}

# The Default user profile sits on the ephemeral OS disk, so write consent on every boot
function Set-ADPConsent {
    if (-not $ADP_ANALYTICS_OPT_IN -or $MAX_VERSION -ne "2027") { return }
    $dir = "C:\Users\Default\AppData\Roaming\Autodesk\ADPSDK\UserConsent"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $ids = "ADSK_PUD_CONTRACTUAL_NECESSITY_DESKTOP", "ADSK_PUD_OPTIMIZATION_IMPROVEMENT_DESKTOP", "ADSK_PUD_GO_TO_MARKET_DESKTOP"
    @{ preferences = @($ids | ForEach-Object { @{ consentId = $_; optIn = $true } }); userActionRequired = $false; userId = "UnNamed"
    } | ConvertTo-Json -Depth 5 | Set-Content -Path "$dir\UnNamed.json" -Encoding UTF8
    Write-Host "Recorded Autodesk ADP opt-in consent in the Default user profile"
}

function Initialize-Junctions {
    foreach ($j in $junctions) {
        New-Item -ItemType Directory -Path $j.Target -Force | Out-Null
        if (Test-Path $j.Link) {
            if ((Get-Item $j.Link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            Remove-Item $j.Link -Recurse -Force
        }
        $parent = Split-Path $j.Link -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        New-Item -ItemType Junction -Path $j.Link -Target $j.Target | Out-Null
        Write-Host "Junction: $($j.Link) -> $($j.Target)"
    }
}

# Registry and services are on the OS disk, so save them with the files
function Export-InstallerState {
    New-Item -ItemType Directory -Path $STATE_BACKUP -Force | Out-Null
    foreach ($key in $REG_KEYS) { reg.exe export "$key" "$STATE_BACKUP\$(($key -split '\\')[-1]).reg" /y 2>&1 | Out-Null }
    foreach ($svc in Get-CimInstance Win32_Service | Where-Object { $_.PathName -match "Autodesk|Chaos|Itoo" }) {
        @{ Name = $svc.Name; DisplayName = $svc.DisplayName; PathName = $svc.PathName; StartMode = $svc.StartMode
        } | ConvertTo-Json | Out-File "$STATE_BACKUP\$($svc.Name).json"
    }
}
function Import-InstallerState {
    if (-not (Test-Path $STATE_BACKUP)) { return }
    foreach ($file in Get-ChildItem "$STATE_BACKUP\*.reg") { reg.exe import "$($file.FullName)" 2>&1 | Out-Null }
    foreach ($file in Get-ChildItem "$STATE_BACKUP\*.json") {
        try {
            $svc = Get-Content $file.FullName | ConvertFrom-Json
            if (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue) { continue }
            $startType = switch ($svc.StartMode) { "Auto" { "auto" } "Disabled" { "disabled" } default { "demand" } }
            sc.exe create $svc.Name binPath= "$($svc.PathName)" start= $startType DisplayName= "$($svc.DisplayName)" | Out-Null
            if ($startType -eq "auto") { Start-Service -Name $svc.Name -ErrorAction SilentlyContinue }
            Write-Host "Registered service: $($svc.Name)"
        } catch { Write-Host "WARNING: could not restore $($file.Name): $_" }
    }
}

$scriptStart = Get-Date

# Validate all CONFIG before doing any work
if ($MAX_VERSION -notmatch '^\d{4}$') { throw "CONFIG MAX_VERSION must be a four digit year, e.g. 2027" }
if ($ADP_ANALYTICS_OPT_IN -isnot [bool]) { throw "CONFIG ADP_ANALYTICS_OPT_IN must be `$true or `$false" }
if (-not $3DS_MAX_INSTALLER_ZIP_S3_URI) { throw "CONFIG 3DS_MAX_INSTALLER_ZIP_S3_URI is required" }
foreach ($name in "3DS_MAX_INSTALLER_ZIP_S3_URI","VRAY_S3_URI","TYFLOW_S3_URI","FOREST_PACK_S3_URI","RAILCLONE_S3_URI","FLOORGENERATOR_S3_URI","MULTITEXTURE_S3_URI") {
    $uri = (Get-Variable $name).Value
    if ($uri -and ($uri -notlike "s3://*" -or $uri -match '[<>]')) { throw "CONFIG $name is not a usable S3 URI: $uri" }
}
if ($MAX_VERSION -eq "2027" -and -not $ADP_ANALYTICS_OPT_IN) {
    Write-Host "WARNING: ADP_ANALYTICS_OPT_IN is false - 2027 render nodes exit -12 at startup. See the README."
}

$MOUNT_PATH = [Environment]::GetEnvironmentVariable("DEADLINE_PERSISTENT_MOUNT", "Machine")
$junctions = @()
if (-not $MOUNT_PATH) {
    Write-Host "No persistent volume - normal install"
    $PERSISTENCE_ENABLED = $false
} else {
    Write-Host "Persistent volume detected at: $MOUNT_PATH"
    $PERSISTENCE_ENABLED = $true
    $SW_PATH = "$MOUNT_PATH\Software"
    $DATA_PATH = "$MOUNT_PATH\SoftwareData"
    $STATE_BACKUP = "$MOUNT_PATH\SoftwareState"
    $INSTALL_MARKER = "$SW_PATH\.install-complete"
    $junctions = @(
        @{ Link = "C:\Program Files\Autodesk"; Target = "$SW_PATH\Autodesk" }
        @{ Link = "C:\Program Files (x86)\Common Files\Autodesk Shared"; Target = "$SW_PATH\AutodeskShared" }
        @{ Link = "C:\ProgramData\Autodesk\ApplicationPlugins"; Target = "$DATA_PATH\ApplicationPlugins" }
    )
    if ($VRAY_S3_URI) { $junctions += @{ Link = "C:\Program Files\Chaos"; Target = "$SW_PATH\Chaos" } }
    if ($FOREST_PACK_S3_URI -or $RAILCLONE_S3_URI) { $junctions += @{ Link = $ITOO_ROOT; Target = "$SW_PATH\ItooSoftware" } }
}

if ($PERSISTENCE_ENABLED -and (Test-Path $INSTALL_MARKER)) {
    Write-Host "=== Restoring from persistent volume ==="
    $t = Get-Date
    Initialize-Junctions
    if (Test-Path "$MAX_ROOT\3dsmaxbatch.exe") {
        # These all live on the OS disk, so put them back rather than reinstalling
        Import-InstallerState
        Set-AllEnvVars
        Set-ADPConsent
        Write-Duration $t "Restore"
        Write-Duration $scriptStart "Total"
        Exit 0
    }
    # Only missing files force a reinstall
    Write-Host "WARNING: volume is missing $MAX_ROOT\3dsmaxbatch.exe - reinstalling"
}
if ($PERSISTENCE_ENABLED) {
    Write-Host "=== First boot - installing to persistent volume ==="
    Initialize-Junctions
}

New-Item -ItemType Directory -Path $DOWNLOADS_PATH, $SETUP_PATH -Force | Out-Null

Write-Host "Downloading installers from S3 (parallel)..."
$maxDownload = Save-URI $3DS_MAX_INSTALLER_ZIP_S3_URI
if ($VRAY_S3_URI) { $vrayDownload = Save-URI $VRAY_S3_URI }
if ($FOREST_PACK_S3_URI) { $fpDownload = Save-URI $FOREST_PACK_S3_URI }
if ($RAILCLONE_S3_URI) { $rcDownload = Save-URI $RAILCLONE_S3_URI }
# Plugin files only need moving into place
$pluginFiles = @()
if ($TYFLOW_S3_URI) { $pluginFiles += @{ Name = "tyFlow"; Download = (Save-URI $TYFLOW_S3_URI) } }
if ($FLOORGENERATOR_S3_URI) { $pluginFiles += @{ Name = "FloorGenerator"; Download = (Save-URI $FLOORGENERATOR_S3_URI) } }
if ($MULTITEXTURE_S3_URI) { $pluginFiles += @{ Name = "MultiTexture"; Download = (Save-URI $MULTITEXTURE_S3_URI) } }

$t = Get-Date
Write-Host "Installing 3ds Max $MAX_VERSION..."
Wait-Download $maxDownload
Expand-Archive -Path $maxDownload.FilePath -DestinationPath $SETUP_PATH -Force
# Shallowest match wins over nested component installers
$maxSetup = Get-ChildItem -Path $SETUP_PATH -Filter "Setup.exe" -Recurse | Sort-Object { $_.FullName.Length } | Select-Object -First 1
if (-not $maxSetup) { throw "3ds Max installer (Setup.exe) not found in $($maxDownload.File)" }
Invoke-WithErrorCapture $maxSetup.FullName "-q"
if (-not (Test-Path $MAX_ROOT)) { throw "3ds Max $MAX_VERSION not found at $MAX_ROOT after install" }
Write-Duration $t "3ds Max"

if ($vrayDownload) {
    $t = Get-Date
    Write-Host "Installing V-Ray for 3ds Max $MAX_VERSION..."
    Wait-Download $vrayDownload
    $vrayConfig = "$SETUP_PATH\vray_config.xml"
    @"
<DefValues>
<Value Name="INSTALL_TYPE" DataType="value">1</Value>
<Value Name="ANONYMOUS_TELEMETRY" DataType="value">0</Value>
<Value Name="PERSONALIZED_TELEMETRY" DataType="value">0</Value>
<Value Name="PKGROOT_SELECT" DataType="value">0</Value>
<Value Name="INSTALLROOT" DataType="value">$VRAY_ROOT</Value>
<Value Name="REMOTE_LICENSE" DataType="value">1</Value>
<Value Name="AUTO_INSTALL_UIMENUS" DataType="value">1</Value>
<Value Name="SHOULDUNINSTALL" DataType="value">0</Value>
<Value Name="VISIT_SPOT3D" DataType="value">0</Value>
</DefValues>
"@ | Out-File -FilePath $vrayConfig -Encoding UTF8
    Invoke-WithErrorCapture $vrayDownload.FilePath @("-gui=0", "-configFile=$vrayConfig", "-quiet=1")
    # V-Ray 7.30.02 and later enable Chaos Cloud Licensing, which breaks Usage Based Licensing
    $setvrl = "$VRAY_PLUGIN\utils\setvrlservice.exe"
    if (Test-Path $setvrl) { Invoke-WithErrorCapture $setvrl "-cloud-server=0" }
    else { Write-Host "WARNING: $setvrl not found - V-Ray Cloud Licensing not disabled" }
    Write-Duration $t "V-Ray"
}

if ($fpDownload) {
    $t = Get-Date
    Write-Host "Installing Forest Pack..."
    Wait-Download $fpDownload
    Invoke-WithErrorCapture $fpDownload.FilePath @("/S", "MAXVER=max$MAX_VERSION-64", "/MAXDIR=$MAX_ROOT", "/LICMODE=rendernode")
    Write-Duration $t "Forest Pack"
}
if ($rcDownload) {
    $t = Get-Date
    Write-Host "Installing RailClone..."
    Wait-Download $rcDownload
    Invoke-WithErrorCapture $rcDownload.FilePath @("/S", "/LICMODE=rendernode")
    Write-Duration $t "RailClone"
}
if ($pluginFiles) {
    New-Item -ItemType Directory -Path $PLUGINS_DIR -Force | Out-Null
    foreach ($plugin in $pluginFiles) {
        Wait-Download $plugin.Download
        Move-Item -Path $plugin.Download.FilePath -Destination "$PLUGINS_DIR\" -Force
        Write-Host "$($plugin.Name) installed to $PLUGINS_DIR\$($plugin.Download.File)"
    }
}

Write-Host "Configuring environment for 3ds Max $MAX_VERSION..."
Set-AllEnvVars
Set-ADPConsent

Write-Host "Installing Deadline Cloud for 3ds Max..."
& "$MAX_PY\python.exe" -m ensurepip
& "$MAX_PY\python.exe" -m pip install deadline-cloud-for-3ds-max
# A native non-zero exit does not trip $ErrorActionPreference
if ($LASTEXITCODE -ne 0) { throw "pip install deadline-cloud-for-3ds-max failed with exit code $LASTEXITCODE" }

if ($PERSISTENCE_ENABLED) {
    Export-InstallerState
    Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Out-File $INSTALL_MARKER
    Write-Host "Install marker written"
}

Write-Duration $scriptStart "Total"
Exit 0
