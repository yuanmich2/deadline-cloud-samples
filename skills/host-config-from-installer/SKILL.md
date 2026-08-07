---
name: host-config-from-installer
description: >
  Interactively install software with the customer, test it, upload the installer to S3, and convert
  the working steps into a host configuration script for AWS Deadline Cloud Service Managed Fleets.
  Use when a customer says "I have an installer", "I want to install X on my fleet", "convert my
  install steps to a host config", or "help me set up X on Deadline Cloud workers". Covers Windows
  `.exe` installers (PowerShell) and Linux installers or packages (Bash).
tags: [skill, host-configuration, deadline-cloud, powershell, bash, installer, service-managed-fleet, windows, linux]
---

# Host Config from Installer

## Overview

This skill walks a customer through installing software on their local machine, verifying it works,
uploading the installer to S3, and converting the verified steps into a host configuration script for
AWS Deadline Cloud Service Managed Fleets.

The generated script is based on commands that were tested and confirmed working, not on guesswork or
templates.

Two things make a host configuration script different from a set of install commands, and both drive
the standards below:

- The script runs unattended at worker startup, with no operator present to read a prompt or retry a
  failed step. A failure that prints nothing looks identical to success.
- The script runs on a fresh host every boot. Nothing the installer wrote to the OS disk on a previous
  boot survives, including machine environment variables and service registrations.

## Usage

Use this skill when:

- A customer has an installer and wants the software running on their Deadline Cloud fleet workers
- A customer wants to convert a manual install process into a host config script
- The software is not covered by an existing specific skill (for example `3dsmax-host-config`)

## Script standards

Every script this skill generates follows the six standards below. They come from the reference
implementations in this repository:

- `host_configuration_scripts/aftereffects/aftereffects_redgiant/install-software.ps1` is the fullest
  reference. Read it before generating a script. It covers a required base install, five optional
  components, license configuration, and persistent volume support.
- `host_configuration_scripts/cinema4d/cinema4d_redgiant/install-software.ps1` is a smaller version of
  the same shape.

Each standard states the rule, then the idiom. Sections marked **Windows** or **Linux** apply only to
that platform. Everything else applies to both.

### Standard 1: One CONFIG block at the top, kept small and hard to get wrong

Put every operator-editable value in a single labeled block before any executable logic. An operator
should be able to configure the script by editing one contiguous region and reading nothing else.

Two goals drive the shape of the block:

**Few parameters.** Every parameter is something an operator can get wrong, so fewer parameters means
fewer ways to misconfigure the script. Expose only what an operator must supply and derive the rest
(see Standard 2).

**Each parameter should be copyable, not assembled.** For every value, ask where the operator gets it
and whether they can paste it without editing. Prefer the form that has a copy affordance somewhere in
the operator's workflow. Avoid any parameter that makes the operator split, join, reformat, or retype
part of a value they already have, because each of those steps is a chance to introduce a typo that the
script cannot detect.

Applying both goals to an installer location gives a single full S3 URI:

```powershell
$AE_INSTALLER_S3_URI = "s3://<bucket>/After Effects_en_US_WIN_64.zip"  # required
```

The S3 console has a "Copy S3 URI" button, so the operator pastes the exact string with no
transcription. One URI also carries the bucket, the full prefix, and the filename together, so it
replaces three parameters with one. A bucket variable plus a key plus a filename would force the
operator to take that same copied string apart by hand.

The same reasoning applies to other value types. A license server endpoint is one `port@host` string
because that is how a license administrator states it. A version number should match how the vendor
writes it, so an operator can read it off an installer filename or an install directory. When two
plausible shapes exist for a value, choose the one the operator can copy from an authoritative source
rather than the one that is tidier in the script.

Remaining rules:

- Required values first, then optional ones under a comment saying that blank skips the component.
- Give each value an inline comment with its expected format or an example. Configuration must not
  depend on the README.
- Where several forms of a value look plausible, such as a bucket name against a bucket ARN against an
  HTTPS URL, state the accepted form inline and validate it (see Standard 3). A wrong-but-plausible
  value that is silently accepted is worse than one that fails immediately.

**Windows (PowerShell)**

```powershell
# CONFIG ================
# Required
$AE_INSTALLER_S3_URI = "s3://<bucket>/After Effects_en_US_WIN_64.zip"  # required

# Optional components. Leave blank to skip.
$RED_GIANT_S3_URI = ""  # e.g. s3://<bucket>/RedGiant-2026.3.0-Win.exe
$MAXON_APP_S3_URI = ""  # required with Red Giant. e.g. s3://<bucket>/Maxon_App_2026.0.1_Win.exe
$RED_GIANT_LICENSE_SERVER = ""  # port@host; blank = UBL. e.g. 7055@my-license-server
# END CONFIG ================
```

**Linux (Bash)**

```bash
# CONFIG ================
# Required
INSTALLER_S3_URI="s3://<bucket>/software-installer.tar.gz"  # required

# Optional. Leave blank to skip.
LICENSE_SERVER=""  # port@host; blank = no license. e.g. 5053@my-license-server
# END CONFIG ================
```

What belongs in CONFIG is anything only the operator knows: where they put the installer, which license
server they run, which version they bought, and whether they consent to an optional behavior. What does
not belong is anything the script can work out for itself, including install directories, plugin
directories, executable paths, installer filenames, and temp paths.

#### Keep secrets out of the script

Never put a secret in the script, in CONFIG or anywhere else. The script body is stored in the fleet's
`HostConfiguration` and is readable by anyone who can read the fleet configuration, which is a wider
audience than the operator who wrote it. A secret pasted into CONFIG is also easy to leak further, because
these scripts get copied between fleets, pasted into tickets, and committed to repositories.

Secrets in this context include license keys and key files, passwords, API tokens, and private
certificates.

A license server endpoint is not a secret. A `port@host` value is a network address, so it belongs in
CONFIG as an ordinary value.

Where the software needs a secret, keep the secret out of the script and put a reference to it in CONFIG
instead. Stage the secret in the customer's own S3 bucket and have the script download it at runtime,
exactly as it downloads an installer, so the CONFIG value is a URI rather than the secret itself:

```powershell
$LENSCARE_LICENSE_S3_URI = ""  # license key file; blank = no license. e.g. s3://<bucket>/Lenscare_ae.key
```

The fleet role already needs `s3:GetObject` for the installers, so this adds no new access path, and S3
bucket policies and encryption then govern the secret rather than the fleet configuration. AWS Secrets
Manager works the same way where the customer already uses it: CONFIG holds the secret's name or ARN and
the script fetches the value at runtime.

Two practices to avoid alongside this: do not echo a secret's value into the log, because worker output
goes to CloudWatch (log the path or the name instead), and do not write a fetched secret anywhere on the
OS disk beyond the location the software requires.

### Standard 2: Derive values instead of hardcoding them

Hardcoded paths and filenames are the most common cause of a host config script that works on one
version of the software and breaks on the next. Derive whatever the script can determine at runtime,
and fail loudly when derivation does not succeed.

A useful test: if a value contains a version number, or repeats a literal that appears elsewhere in the
script, it is a candidate for derivation.

**Derive the installer filename from the S3 URI.** Never add a separate filename variable.

```powershell
$file = Split-Path -Leaf $uri
```

```bash
file="$(basename "$INSTALLER_S3_URI")"
```

**Discover install directories rather than naming them.** Vendors put the version in the directory
name, so a literal path pins the script to one release. Search for the directory and fail if it is
absent:

```powershell
function Set-AERenderEnvVar {
    $aeDir = Get-ChildItem "C:\Program Files\Adobe" -Directory -Filter "Adobe After Effects*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $aeDir) { throw "After Effects install directory not found under C:\Program Files\Adobe" }
    $aeRender = Join-Path $aeDir.FullName "Support Files\aerender.exe"
    if (-not (Test-Path $aeRender)) { throw "aerender.exe not found at $aeRender" }
    Set-MachineEnvVar "AERENDER_EXECUTABLE" $aeRender
    Write-Host "Detected After Effects: $($aeDir.Name)"
}
```

The same script now works across After Effects releases without an edit.

**Find an archive's entry point by searching, not by assuming a subpath.** Archive layouts are not
guaranteed. An After Effects Feature Restricted License archive extracts a folder named
`After_Effects_FRL` where the standard archive extracts `After Effects`, so a hardcoded
`After Effects\Build\setup.exe` crashes on the FRL archive. Extract into a dedicated temp directory the
script controls, then search:

```powershell
$aeTempExtract = "$DOWNLOADS_PATH\ae_temp"
Expand-Archive -Path $aeDownload.FilePath -DestinationPath $aeTempExtract -Force
$aeSetup = Get-ChildItem -Path $aeTempExtract -Filter "setup.exe" -Recurse | Select-Object -First 1
if (-not $aeSetup) { throw "After Effects installer (setup.exe) not found in archive" }
Invoke-WithErrorCapture $aeSetup.FullName "--silent"
```

Extracting into a dedicated directory per archive matters when a script unpacks several archives.
Sharing one temp directory lets a recursive search match a file from a previous extraction.

**Always throw when discovery fails.** A search that returns nothing must stop the script with a
message naming what was not found. Never continue with an empty path, because the resulting error
surfaces much later and points somewhere unrelated.

**What cannot be derived, and that is fine.** Silent install flags are vendor specific and must be
discovered by testing (see the workflow below). License server endpoints and S3 URIs are operator
facts. Put these in CONFIG with an inline example rather than inline in the body of the script.

### Standard 3: Fail fast, cheap work before expensive work

Order every script this way:

1. Strict mode and error trap
2. CONFIG block
3. Persistence detection, including early restore and exit where applicable (Standard 6)
4. Validation of all CONFIG values
5. All downloads
6. Installs and system changes
7. Persistence finalize (Standard 6)

Validation and downloads are cheap and are the steps most likely to fail, so they run before installs,
which are slow. A malformed URI then fails in seconds instead of after a twenty minute install.

**Strict mode**

```powershell
$ErrorActionPreference = "Stop"
```

```bash
set -euo pipefail
```

**Validate before downloading, and name the offending value.** Check required values are present, and
check cross field dependencies, which are easy to miss:

```powershell
if (-not $AE_INSTALLER_S3_URI) { throw "Missing After Effects installer archive" }
if ($RED_GIANT_S3_URI) {
    if (-not $MAXON_APP_S3_URI) { throw "Missing Red Giant dependency: Maxon app" }
    if (-not $WEBVIEW2_S3_URI) { throw "Missing Red Giant dependency: WebView2" }
}
if ($RSMB_S3_URI -and $RSMB_LICENSE_SERVER -and -not $RSMB_LICENSING_S3_URI) { throw "CONFIG RSMB_LICENSING_S3_URI is required when RSMB_LICENSE_SERVER is set" }
```

**Verify each download by exit code and by file presence.** An `aws s3 cp` that fails still leaves the
script running under some conditions, and a zero exit code does not guarantee a file on disk.

**Start downloads in parallel, then wait immediately before the install that needs the file.** Downloads
are network bound and installs are ordered, so overlapping them cuts startup time noticeably on a script
with several components. `Save-URI` starts a download and returns a handle, `Wait-Download` blocks and
validates:

```powershell
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
```

### Standard 4: Make every failure visible in CloudWatch

Worker output goes to the CloudWatch log group `/aws/deadline/farm-<farm-id>/fleet-<fleet-id>`. Anything
not written to the captured stream is lost, and a failed unattended install that prints nothing is
indistinguishable from success.

**Declare one logging mechanism near the top.** Do not add per line redirection.

```powershell
$ErrorActionPreference = "Stop"
trap { Write-Output "ERROR: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; exit 1 }
```

The trap prints the message, the failing line, and the stack, then exits non-zero. Without the position
and stack, a one line error in a long script is hard to place.

```bash
exec 2>&1   # merge stderr into the captured stdout stream
set -x      # trace each command
```

**Capture child process output.** This is the highest value item in this standard. A silent installer
writes its own diagnostics to its own stdout and stderr, and `Start-Process` discards both unless
redirected. Without capture, a failing installer yields an exit code and nothing else. Wrap every
external install call:

```powershell
function Invoke-WithErrorCapture($path, $argList){
    $outFile = New-TemporaryFile
    $errFile = New-TemporaryFile
    $p = Start-Process -FilePath $path -ArgumentList $argList -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outFile.FullName -RedirectStandardError $errFile.FullName
    if ($p.ExitCode -ne 0) {
        throw "Command failed with exit code $($p.ExitCode): $path $argList`n$(Get-Content $outFile -Raw)$(Get-Content $errFile -Raw)"
    }
}
```

**Never suppress errors.** Do not apply `-ErrorAction SilentlyContinue` broadly. Limit it to a probe
whose failure is an expected outcome the script handles, such as testing whether a service already
exists.

**Log a progress line per operation and time each phase.** Timings identify which component is slow when
a fleet is slow to come up:

```powershell
function Write-Duration($start, $name){ Write-Host "$($name): $(((Get-Date) - $start).ToString('hh\:mm\:ss'))" }
```

**Warn when a degraded configuration is intentional.** Installing a plugin with no license succeeds but
produces watermarked renders, so say so rather than passing over it:

```powershell
Write-Host "WARNING: BORIS_LICENSE_SERVER blank - installed Boris Sapphire without license (renders will be watermarked)"
```

### Standard 5: Stay within the character limit

The Deadline Cloud `HostConfiguration` `scriptBody` field holds at most 15,000 characters
([API reference](https://docs.aws.amazon.com/deadline-cloud/latest/APIReference/API_HostConfiguration.html)).
A script that exceeds the limit cannot be applied to a fleet at all, so treat the limit as a hard
constraint and check the character count before finishing.

Keep scripts compact:

- Limit comments to labeling the CONFIG block and identifying each operation. Add no boilerplate.
- Write helpers as single line functions where practical.
- Reuse derived values rather than recomputing or restating them.

If a script does not fit, split it by component group rather than by version. Version differences are
usually one interpolated variable and cost almost nothing, while each additional component costs a
validate block, a download, an install, and its environment setup.

### Standard 6: Use a persistent volume when one is attached (Windows)

Where a fleet attaches a persistent volume, Deadline Cloud exposes its mount path in the
`DEADLINE_PERSISTENT_MOUNT` machine environment variable. A script that understands the variable installs
once and restores on later boots instead of reinstalling, which cuts worker startup time substantially.

Detection is automatic. Do not add a CONFIG flag for it.

```powershell
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
```

Three cases follow:

1. No mount path: install normally, with no persistence behavior.
2. Mount path present, no marker file: create directory junctions redirecting the install paths onto the
   volume, install into them, export service registrations to the volume, write the marker.
3. Mount path present, marker file found: recreate the junctions against the populated volume,
   reregister the services, reset the machine environment variables, then exit without downloading or
   installing.

Case 3 must still set machine environment variables and reregister services, because the OS disk is new
each boot even though the volume is not. Gate each junction on whether its component is enabled in
CONFIG, so a skipped component creates no junctions. See the After Effects reference for
`Initialize-Junctions`, `Export-InstallerState`, and `Import-InstallerState`.

Tell the operator to test case 3 explicitly if they plan to use a persistent volume, and record the
instruction in the README (see Step 9). Case 3 is the one that fails quietly: if restore is broken the
script reinstalls on every boot, so renders still succeed and only startup time regresses. Nothing in the
logs reports an error, so an operator who never compares a second boot against a first keeps paying for a
volume that saves them nothing.

No equivalent pattern is established for Linux fleets in this repository. Do not invent one. Generate a
Linux script without persistence support unless the customer asks, and then work out and test the
approach with them.

## Prerequisites

Confirm the customer has:

- The installer file available locally, on the same platform the fleet runs
- AWS CLI installed and configured with credentials that have `s3:PutObject` access
- An S3 bucket in the same region as their Deadline Cloud farm, or willingness to create one
- PowerShell (Windows) or Bash (Linux) available locally

## Workflow

Follow these steps in order. At each step, run the command and check the output. Do not continue until
the step succeeds.

### Step 1: Gather information

Ask the customer:

- What software are they installing, including the version?
- Where is the installer file locally, as a full path?
- Which platform does the target fleet run, Windows or Linux?
- Do they have an S3 bucket already, or do they need one created?
- What is their AWS region?
- Does the fleet attach a persistent volume? (Windows only, see Standard 6)

### Step 2: Find the silent install flags

Silent flags cannot be derived, so discover them by testing. Run the installer with common flag sets in
this order until one succeeds.

**Windows**

```powershell
# Attempt 1 - NSIS style
Start-Process "<installer-path>" -ArgumentList '/S' -Wait -PassThru
# Attempt 2 - Inno Setup style
Start-Process "<installer-path>" -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
# Attempt 3 - MSI wrapped in exe
Start-Process "<installer-path>" -ArgumentList '/quiet', '/norestart' -Wait -PassThru
# Attempt 4 - InstallShield style
Start-Process "<installer-path>" -ArgumentList '-s' -Wait -PassThru
# Attempt 5 - InstallBuilder style, common for VFX plugin vendors
Start-Process "<installer-path>" -ArgumentList '--mode', 'unattended', '--unattendedmodeui', 'none' -Wait -PassThru
```

After each attempt, check whether the software installed by looking under `C:\Program Files\` or
`C:\Program Files (x86)\`. Ask the customer to confirm.

If none work, ask the customer to check the installer's documentation, or run `<installer-path> /?` or
`<installer-path> /help`.

**Linux**

Silent behavior depends on the package format. A `.run` or InstallBuilder binary usually takes
`--mode unattended`. Distribution packages install non-interactively with `yum install -y` or
`apt-get install -y`. A tarball needs no flags, only extraction.

Record the exact working flags. They go into the generated script verbatim.

### Step 3: Verify the install

Confirm the software runs before generating anything.

```powershell
Get-ChildItem "C:\Program Files\<SoftwareName>"
& "C:\Program Files\<SoftwareName>\<executable>.exe" --version
```

Note the actual install directory name here, including how the version appears in it. Standard 2 needs a
search pattern that matches this directory across versions, for example `Adobe After Effects*` for
`Adobe After Effects 2026`.

### Step 4: Capture environment changes

An installer run interactively writes environment variables that will not exist on a fleet worker, so the
script must set them explicitly.

```powershell
[System.Environment]::GetEnvironmentVariables('Machine') | Format-List
```

```bash
env | sort
```

Record every new variable and PATH entry. Where a value contains an install path, plan to build it from
the directory discovered in Standard 2 rather than pasting the literal.

### Step 5: Ensure the S3 bucket exists

```powershell
aws s3 mb s3://<bucket-name> --region <region>
```

If the bucket exists, verify access:

```powershell
aws s3 ls s3://<bucket-name>
```

The fleet's IAM role needs `s3:GetObject` on this bucket. Without it, workers cannot download the
installer at runtime, and the failure appears only in the worker logs.

### Step 6: Upload the installer

```powershell
aws s3 cp "<local-installer-path>" s3://<bucket-name>/<installer-filename>
```

Confirm the upload:

```powershell
aws s3 ls s3://<bucket-name>/<installer-filename>
```

The full S3 URI of the uploaded object becomes the single CONFIG value for this installer.

### Step 7: Generate the script

Read the After Effects reference script first, then generate a script applying all six standards.

Place it under `host_configuration_scripts/<software-name>/`. Check the target directory's existing
convention before choosing a layout, because it varies:

- `aftereffects/` and `cinema4d/` use a subfolder per script with its own README
- `3dsmax/` uses flat top-level scripts sharing one README index

For new software with no existing directory, use
`host_configuration_scripts/<software-name>/install-software.ps1` plus a `README.md`.

**Windows skeleton**

```powershell
$ErrorActionPreference = "Stop"
trap { Write-Output "ERROR: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; exit 1 }

# CONFIG ================
# Required
$INSTALLER_S3_URI = "s3://<bucket>/<installer-filename>"  # required
# Optional. Leave blank to skip.
$LICENSE_SERVER = ""  # port@host; blank = no license. e.g. 5053@my-license-server
# END CONFIG ================

function Invoke-WithErrorCapture($path, $argList){ <# see Standard 4 #> }
function Save-URI($uri){ <# see Standard 3 #> }
function Wait-Download($download){ <# see Standard 3 #> }
function Set-MachineEnvVar($name, $value){ [Environment]::SetEnvironmentVariable($name,$value,"Machine") }
function Write-Duration($start, $name){ Write-Host "$($name): $(((Get-Date) - $start).ToString('hh\:mm\:ss'))" }

# Persistence detection, see Standard 6

$scriptStartTime = Get-Date
$DOWNLOADS_PATH = "C:\Temp"

# Validate
if (-not $INSTALLER_S3_URI) { throw "CONFIG INSTALLER_S3_URI is required" }

# Download
$download = Save-URI $INSTALLER_S3_URI

# Install
$startTime = Get-Date
Write-Host "Installing <software>..."
Wait-Download $download
Invoke-WithErrorCapture $download.FilePath "<verified-silent-flags>"

# Configure, deriving paths rather than hardcoding, see Standard 2
$installDir = Get-ChildItem "C:\Program Files" -Directory -Filter "<SoftwareName>*" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $installDir) { throw "<SoftwareName> install directory not found under C:\Program Files" }
Set-MachineEnvVar "<VAR_NAME>" $installDir.FullName
Write-Duration $startTime "<software>"

Write-Duration $scriptStartTime "Total"
Exit 0
```

**Linux skeleton**

```bash
#!/usr/bin/env bash
set -euo pipefail
exec 2>&1

# CONFIG ================
INSTALLER_S3_URI="s3://<bucket>/<installer-filename>"  # required
# END CONFIG ================

[ -n "$INSTALLER_S3_URI" ] || { echo "ERROR: CONFIG INSTALLER_S3_URI is required"; exit 1; }

DOWNLOADS_PATH="/tmp/software_setup"
mkdir -p "$DOWNLOADS_PATH"
installer="$DOWNLOADS_PATH/$(basename "$INSTALLER_S3_URI")"

echo "Downloading installer..."
aws s3 cp --no-progress "$INSTALLER_S3_URI" "$installer"
[ -f "$installer" ] || { echo "ERROR: download failed: $INSTALLER_S3_URI"; exit 1; }

echo "Installing..."
chmod +x "$installer"
"$installer" <verified-silent-flags>

echo "Install complete"
```

### Step 8: Run the pre-flight checks

Run these checks on the generated script before testing it on a worker. Each one catches a class of error
that is cheap to find here and slow to find on a fleet, where a single iteration costs a worker launch.

**Character count against the limit.** A script over 15,000 characters cannot be applied to a fleet at
all, so check the count before anything else. Count characters, not bytes, because a non-ASCII character
costs more than one byte and would make a byte count read high:

```powershell
(Get-Content -Raw "host_configuration_scripts/<software-name>/install-software.ps1").Length
```

If the count is over the limit, split by component group as described in Standard 5.

**Syntax parse without executing.** A syntax error otherwise surfaces only when a worker runs the script.
Parse it in place:

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile("<path-to-script>", [ref]$null, [ref]$errors) | Out-Null
if ($errors) { $errors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" } } else { "No syntax errors" }
```

For a Bash script, use `bash -n <path-to-script>`.

**Leftover placeholders.** A placeholder left in the body rather than in CONFIG produces a confusing
runtime failure. Search for the ones this skill's templates use:

```bash
grep -n "<bucket>\|your-bucket-name\|<software-name>\|<verified-silent-flags>\|<SoftwareName>\|TODO" <path-to-script>
```

Placeholders inside the CONFIG block are expected, since the operator fills them in. Placeholders below
the CONFIG block are bugs.

**CONFIG variables all used, all used variables declared.** A CONFIG value the script never reads is a
value the operator will set with no effect, and a variable the script reads but never declares is a
failure waiting for the first run. Check both directions: every variable declared in the CONFIG block
appears again below it, and every `$VARIABLE` referenced below the CONFIG block is either declared there,
derived in the body, or a PowerShell built-in.

**Every install call goes through the error-capturing wrapper.** Search for bare `Start-Process` calls
that bypass `Invoke-WithErrorCapture`. Each one is an installer whose failure output would be discarded:

```bash
grep -n "Start-Process" <path-to-script>
```

The only expected matches are inside `Invoke-WithErrorCapture` and `Save-URI`.

### Step 9: Write the README

Follow the convention of the target directory, either a per-script README or a row in a shared index.
Include:

- What the script installs
- Every CONFIG value, its format, and whether it is required
- Installation guide: create the bucket, upload the installer, configure the fleet, grant the IAM role
  `s3:GetObject`, test
- A note that host configuration changes affect only workers launched after the update
- A recommendation to set min worker count to 1 and check the CloudWatch log group
  `/aws/deadline/farm-<farm-id>/fleet-<fleet-id>` before production use

Where the script supports persistence, the README MUST also tell the operator to test the restore path if
they plan to use a persistent volume, and MUST explain why a broken restore is easy to miss:

- The script detects a persistent volume automatically and needs no configuration to enable it
- A first boot installs to the volume. A later boot should restore from it and skip the install
- The operator should reboot the worker after the first successful boot and confirm from the CloudWatch
  logs that the second boot restored rather than reinstalled
- A broken restore path does not break rendering. The script falls back to reinstalling on every boot, so
  the fleet still works and only startup time regresses. Without deliberately checking the second boot,
  the operator loses the entire benefit of the volume and sees no error telling them so

## Common mistakes

Configuration:

- Making the operator assemble a value they already hold as one string. Splitting an installer location
  into a bucket variable plus a key plus a filename is the common case: the operator has to take a copied
  S3 URI apart by hand, and three parameters replace one.
- Exposing a value the script can discover, such as an install directory or a plugin path.
- Omitting the expected format from a CONFIG comment, which forces the operator into the README.
- Accepting a value in several plausible shapes without validating which one arrived, so a bucket ARN
  pasted where a bucket name was wanted fails somewhere unrelated later.

Hardcoding:

- Naming an install directory with its version in it, which breaks on the next release. Search for the
  directory instead.
- Assuming a subfolder path inside an extracted archive. Search for the entry point.
- Extracting several archives into one shared temp directory, which lets a recursive search match the
  wrong file.
- Continuing after a failed search instead of throwing.

Error handling:

- Calling an installer without capturing its stdout and stderr, which reduces a diagnosable failure to a
  bare exit code.
- Omitting `-Wait` from `Start-Process`, which lets the script continue before the install finishes.
- Applying `-ErrorAction SilentlyContinue` broadly rather than to a single expected-failure probe.
- Installing before validating, so a bad URI wastes a full install cycle.
- Treating a zero exit code from `aws s3 cp` as proof the file is on disk. Check the path too.

Fleet specifics:

- Relying on environment variables the interactive installer set. Set them explicitly at Machine scope.
- Forgetting `s3:GetObject` on the fleet IAM role.
- Omitting `Exit 0` at the end of a PowerShell script.
- Assuming anything on the OS disk survives a reboot. Only a persistent volume survives.
- Exceeding 15,000 characters, which makes the script impossible to apply to a fleet.
