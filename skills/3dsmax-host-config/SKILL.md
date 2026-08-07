---
name: 3dsmax-host-config
description: >
  Create or update 3ds Max host configuration scripts for AWS Deadline Cloud Service Managed Fleets.
  Use when asked to "add a 3ds Max host config script", "create a host configuration for 3ds Max",
  "add support for 3ds Max YEAR", "update V-Ray to version X", "add Forest Pack", "update Forest Pack",
  "add RailClone", "add tyFlow", "add Corona", or when any new 3ds Max version or plugin combination
  needs a host configuration script.
tags: [skill, 3dsmax, host-configuration, deadline-cloud, powershell, service-managed-fleet]
---

# 3ds Max Host Configuration Script Builder

## Overview

This skill creates host configuration PowerShell scripts for AWS Deadline Cloud Windows Service Managed
Fleets. These scripts install 3ds Max (and optionally renderer plugins) onto worker hosts at fleet
startup, since 3ds Max requires administrative access to install.

All scripts live under `host_configuration_scripts/3dsmax/` and follow a consistent structure.

Plugin-specific instructions are in `skills/3dsmax-host-config/add-ons/`. Each `.md` file there is
a self-contained building block. When a customer needs a plugin, find the relevant add-on and
incorporate it into the ps1.

### Script standards

The `host-config-from-installer` skill defines six robustness standards that every host configuration
script in this repository follows. Read `skills/host-config-from-installer/SKILL.md` before writing a
script. In short:

1. **One CONFIG block at the top, kept small and hard to get wrong.** All editable values in one labeled
   block, each with its format inline, required values first and optional ones marked as skippable when
   blank. Every parameter should be a value the operator can copy verbatim from somewhere authoritative
   rather than assemble by hand, and there should be as few of them as possible.
2. **Derive values instead of hardcoding them.** Filenames from S3 URIs, install directories by search,
   archive entry points by search. Throw when a search finds nothing.
3. **Fail fast.** Strict mode, validate all CONFIG, download everything, then install.
4. **Make failures visible in CloudWatch.** One error trap near the top, and capture installer stdout and
   stderr so a failed silent install reports a reason instead of a bare exit code.
5. **Stay under 15,000 characters**, the hard limit on the `HostConfiguration` `scriptBody` field.
6. **Use a persistent volume when `DEADLINE_PERSISTENT_MOUNT` is set.** Install once, restore afterwards.

Never put a secret in the script. The script body is stored in the fleet's `HostConfiguration` and is
readable by anyone who can read the fleet configuration, so license keys, passwords, and API tokens must
not appear in CONFIG or anywhere else in the file. Stage the secret in the customer's S3 bucket and put its
URI in CONFIG instead, the same way installers are handled. A license server endpoint such as `port@host`
is a network address rather than a secret, so it belongs in CONFIG as an ordinary value. See "Keep secrets
out of the script" in `skills/host-config-from-installer/SKILL.md`.

`host_configuration_scripts/aftereffects/aftereffects_redgiant/install-software.ps1` is the reference
implementation of all six. The 3ds Max specific requirements below sit on top of them, and where the two
appear to conflict, the standards win.

## Usage

Use this skill when:
- A new 3ds Max version needs a host configuration script
- A new plugin combination needs a script for an existing or new version
- An existing script needs its 3ds Max version, renderer version, or plugin version bumped
- Someone asks "add host config for 3ds Max X", "update to V-Ray 8", or "bump 3ds Max to 2026"

The add-ons in this skill (V-Ray, Corona, tyFlow, AEC plugins) are only supported
as part of a 3ds Max installation. If the customer asks to install a plugin standalone without
3ds Max, let them know this skill only covers 3ds Max + plugin combinations and direct them to
use the `host-config-from-installer` skill instead.

## Core Concepts

- Scripts are PowerShell (`.ps1`) targeting Windows Service Managed Fleets
- Each script downloads installers from a customer-owned S3 bucket using the AWS CLI (`aws s3 cp`)
- All editable values sit in one CONFIG block at the top of the script, before any executable logic,
  delimited by `# CONFIG ================` and `# END CONFIG ================`. Required values come
  first, then optional ones under a comment stating that blank skips the component. Each value carries an
  inline comment giving its format, so configuring the script never requires opening the README
- Each installer/plugin gets its own full S3 URI variable (e.g. `$3DS_MAX_INSTALLER_ZIP_S3_URI`). Do NOT
  use a shared `$BUCKET_NAME` + filename pattern. The operator copies a complete URI out of the S3 console
  with one button, so taking that string apart into bucket, prefix, and filename parameters adds three
  chances to mistype something they already had correct
- Derive the installer filename from its S3 URI with `Split-Path -Leaf`. Do NOT add a filename variable
- Set `$MAX_VERSION` once in CONFIG and interpolate it into every path and version-suffixed environment
  variable name. Do NOT repeat the year as a literal, because a missed occurrence during a version bump is
  the most common bug in these scripts
- After installing, confirm the 3ds Max directory exists and throw a named error if it does not, rather
  than letting a later step fail on a path that was never created
- The 3ds Max installer variable MUST include a comment linking to the zip creation guide:
  `# Guide on how to create the 3ds Max installer zip file: https://github.com/aws-deadline/deadline-cloud-samples/blob/mainline/host_configuration_scripts/3dsmax/README.md`
- After installing 3ds Max, every script MUST set these environment variables at Machine scope, each built
  from `$MAX_ROOT` rather than a repeated literal path:
  - `Path`: add `$MAX_ROOT`
  - `3DSMAX_EXECUTABLE`: `$MAX_ROOT\3dsmaxbatch.exe`
  - `PYTHONPATH`: the `$MAX_ROOT` Python and Scripts dirs
  - `Path`: also add the Python and Scripts dirs
- Every script MUST install `deadline-cloud-for-3ds-max` via the bundled Python pip
- Scripts MUST end with `Exit 0`
- Each script lives directly under `host_configuration_scripts/3dsmax/`; a single shared `README.md` there documents every script with one sample-index row

## Workflow

You MUST follow these steps in order.

### Step 1: Clarify the request

Ask the user (if not already specified):
- Which 3ds Max version? (e.g. 2026, 2027)
- Any renderer or plugin? (V-Ray, Corona, tyFlow, Forest Pack, RailClone, none)
- If a renderer: which version?

### Step 2: Find the closest existing script as a template

Look in `host_configuration_scripts/3dsmax/` for the most similar existing script and read it in full.

**If updating an existing script** (e.g. bumping 3ds Max 2025 to 2026, or V-Ray 7 to 8):
- Create a new script at the directory root. Do not edit the existing one
- Update every version occurrence: `$VARIABLES`, `Write-Host` messages, install paths, env var names
  (e.g. `VRAY_FOR_3DSMAX2025_MAIN` to `VRAY_FOR_3DSMAX2026_MAIN`)

### Step 3: Determine the script file name

Scripts live directly under `host_configuration_scripts/3dsmax/` (no per-script subfolder). Follow the existing naming convention:

- Base only: `3dsmax-<YEAR>.ps1`
- One plugin: `3dsmax-<YEAR>-and-<plugin>.ps1`
- Multiple plugins: `3dsmax-<YEAR>-<plugin1>-and-<plugin2>.ps1`

When in doubt, look at the existing script names in `host_configuration_scripts/3dsmax/`.
### Step 4: Write the script

Structure, in this order. The ordering puts cheap failures before expensive ones, per Standard 3:

1. Strict mode and error trap
2. CONFIG block: `$MAX_VERSION`, one full S3 URI per installer/plugin, plus any license values
3. Helper functions: `Invoke-WithErrorCapture`, `Save-URI`, `Wait-Download`, `Set-MachineEnvVar`,
   `Write-Duration`
4. Persistence detection and junction set, where the fleet uses a persistent volume
5. Validation: every required CONFIG value, plus cross-field dependencies between a plugin and its
   licensing files
6. Start all downloads in parallel
7. Install 3ds Max: `Expand-Archive`, then `Setup.exe -q`
8. For each plugin, find its add-on in `skills/3dsmax-host-config/add-ons/`, wait for its download, then
   run its silent installer
9. Configure environment for 3ds Max, then for each plugin (from add-on)
10. Install Deadline Cloud: `python.exe -m ensurepip` then `pip install deadline-cloud-for-3ds-max`
11. Persistence finalize: export services, write the install marker
12. `Exit 0`

Key patterns:

```powershell
$ErrorActionPreference = "Stop"
trap { Write-Output "ERROR: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; exit 1 }

# CONFIG ================
# Required
$MAX_VERSION = "2027"  # required. format: YYYY
# Guide on how to create the 3ds Max installer zip file: https://github.com/aws-deadline/deadline-cloud-samples/blob/mainline/host_configuration_scripts/3dsmax/README.md
$3DS_MAX_INSTALLER_ZIP_S3_URI = "s3://<bucket>/3ds-max-2027.zip"  # required

# Optional components. Leave blank to skip.
$VRAY_S3_URI = ""  # e.g. s3://<bucket>/vray_adv_70020_max_x64.exe
# END CONFIG ================

# Derive the install root from $MAX_VERSION once, then reuse it everywhere
$MAX_ROOT = "C:\Program Files\Autodesk\3ds Max $MAX_VERSION"

# Validate before downloading anything
if (-not $MAX_VERSION) { throw "CONFIG MAX_VERSION is required" }
if (-not $3DS_MAX_INSTALLER_ZIP_S3_URI) { throw "CONFIG 3DS_MAX_INSTALLER_ZIP_S3_URI is required" }

# Downloads run in parallel; Save-URI derives the filename from the URI
$maxDownload = Save-URI $3DS_MAX_INSTALLER_ZIP_S3_URI
if ($VRAY_S3_URI) { $vrayDownload = Save-URI $VRAY_S3_URI }

# Install 3ds Max. Setup.exe is at the root after extracting
Wait-Download $maxDownload
Expand-Archive -Path $maxDownload.FilePath -DestinationPath "C:\3dsmax_setup" -Force
Invoke-WithErrorCapture "C:\3dsmax_setup\Setup.exe" "-q"

# Confirm the install landed before depending on its paths
if (-not (Test-Path $MAX_ROOT)) { throw "3ds Max $MAX_VERSION not found at $MAX_ROOT after install" }

# Set env vars, built from $MAX_ROOT rather than repeated literals
Set-MachineEnvVar "3DSMAX_EXECUTABLE" "$MAX_ROOT\3dsmaxbatch.exe"

# Install deadline-cloud-for-3ds-max with the bundled Python
& "$MAX_ROOT\Python\python.exe" -m ensurepip
& "$MAX_ROOT\Python\python.exe" -m pip install deadline-cloud-for-3ds-max
```

`Invoke-WithErrorCapture` replaces bare `Start-Process ... -Wait` for every installer call. `Setup.exe -q`
and the plugin installers write their diagnostics to their own stdout and stderr, which
`Start-Process` discards. Without capture, a failed 3ds Max install produces an exit code and no
explanation. See Standard 4 in `skills/host-config-from-installer/SKILL.md` for the function body.

### Step 4a: Persistent volume support

Where the fleet attaches a persistent volume, add persistence support per Standard 6. Detection reads
`DEADLINE_PERSISTENT_MOUNT` and needs no CONFIG flag. Junction the 3ds Max install path and each enabled
plugin's paths onto the volume, gating each junction on whether its component's S3 URI is set:

```powershell
$junctions = @(
    @{ Link = $MAX_ROOT; Target = "$SW_PATH\3dsMax$MAX_VERSION" }
    @{ Link = "C:\ProgramData\Autodesk"; Target = "$DATA_PATH\Autodesk" }
)
if ($VRAY_S3_URI) {
    $junctions += @{ Link = "C:\Program Files\Chaos Group"; Target = "$SW_PATH\ChaosGroup" }
}
```

On a boot where the install marker is present, recreate the junctions, reregister services, reset the
machine environment variables, and exit before downloading. Machine environment variables and service
registrations live on the OS disk, which is new each boot, so restoring them is required even though the
installed files persist.

### Step 5: Document the script in the shared README

All scripts share a single `host_configuration_scripts/3dsmax/README.md`. Do NOT create a per-script README. Add a row for the new script to the sample-index table under its 3ds Max version section (`### 3ds Max <YEAR>`) with:
- A link to the `.ps1`
- What it installs
- Extra vendor installers to stage in S3 (V-Ray, Corona, tyFlow, Forest Pack, RailClone, etc.), or a dash if none

If a `### 3ds Max <YEAR>` section does not exist yet, add one in version order.
### Step 6: Test the script locally and on a fleet worker

First run the pre-flight checks, which catch errors far more cheaply than a worker launch does. Step 8 of
`skills/host-config-from-installer/SKILL.md` covers each one in full:

- **Character count against the 15,000 limit.** Check this first, because a script over the limit cannot be
  applied to a fleet at all. Count characters rather than bytes:
  ```powershell
  (Get-Content -Raw "host_configuration_scripts/3dsmax/<script-name>.ps1").Length
  ```
- **Syntax parse** with `[System.Management.Automation.Language.Parser]::ParseFile`, so a syntax error does
  not wait for a worker to find it
- **Leftover placeholders** below the CONFIG block, such as `<bucket>`, `<YEAR>`, or `TODO`. Placeholders
  inside the CONFIG block are expected
- **Version literals**, a 3ds Max specific check: search the script for the bare year and confirm every hit
  is either in the CONFIG block or interpolated from `$MAX_VERSION`. A stray literal year is the usual cause
  of a version bump that half works
  ```bash
  grep -n "3ds Max 20\|3DSMAX20\|max20" host_configuration_scripts/3dsmax/<script-name>.ps1
  ```
- **Bare `Start-Process` calls** that bypass `Invoke-WithErrorCapture` and would discard installer output

Then test it:
1. Run the generated `.ps1` locally on a fresh Windows machine to verify the install succeeds end-to-end
2. Verify 3ds Max installed correctly:
   ```powershell
   & "C:\Program Files\Autodesk\3ds Max <YEAR>\3dsmaxbatch.exe" -help
   ```
3. Configure a Service Managed Fleet with the script, set min worker count to 1, and wait for a worker to start
4. If the script includes V-Ray, submit the `sunflower_sphere` test bundle against the fleet to verify rendering works end-to-end:
   ```
   deadline bundle submit host_configuration_scripts/3dsmax/examples/sunflower_sphere
   ```
   The job should complete and produce a rendered sphere with a sunflower texture.
5. For other plugin combinations, create a minimal job bundle that exercises the plugin and submit it to the fleet to confirm the setup is good before production use.
6. If the script supports a persistent volume and the customer plans to use one, reboot the worker after the
   first successful boot and confirm from the CloudWatch logs that the second boot restored from the volume
   instead of reinstalling. Tell the customer to do the same on their own fleet, and record the instruction
   in the shared README row or its notes.

   A broken restore path does not break rendering. The script falls back to reinstalling on every boot, so
   jobs still succeed and only startup time regresses, with no error in the logs to point at the cause.
   Unless the second boot is checked deliberately, the customer pays for a volume that saves them nothing.

## Common Mistakes

3ds Max specifics:

- Using a shared `$BUCKET_NAME` variable. Each installer must have its own full S3 URI variable instead
- Using `$FOLDER_NAME\Setup.exe`. After `Expand-Archive`, `Setup.exe` is at the root of `C:\3dsmax_setup\`
- Missing `Exit 0` at the end
- Setting env vars before installing. Always install first, then configure
- Using `&&` as a command separator. PowerShell uses `;` or separate lines
- Forgetting `-m ensurepip` before `-m pip install`
- When bumping versions: forgetting to update year suffixes in env var names
  (e.g. `VRAY_FOR_3DSMAX2025_MAIN` to `VRAY_FOR_3DSMAX2026_MAIN`). Interpolating `$MAX_VERSION` instead of
  writing the year as a literal prevents this class of bug

Robustness standards, the full list is in `skills/host-config-from-installer/SKILL.md`:

- Scattering editable values through the script instead of gathering them into one CONFIG block
- Omitting the format from a CONFIG comment, which pushes the operator to the README
- Repeating `C:\Program Files\Autodesk\3ds Max <YEAR>` as a literal instead of deriving `$MAX_ROOT` once
- Calling `Start-Process` for an installer without capturing stdout and stderr, which turns a diagnosable
  failure into a bare exit code
- Installing before validating CONFIG, so a typo in an S3 URI costs a full install cycle
- Depending on a path the install was supposed to create without checking it exists
- Adding a CONFIG flag to turn persistence on. Detection is automatic from `DEADLINE_PERSISTENT_MOUNT`
- Restoring from a persistent volume without resetting machine environment variables, which live on the
  OS disk and are gone after a reboot
- Shipping persistence support without checking a second boot, so a broken restore silently reinstalls
  every time and the volume delivers nothing
- Putting a license key, password, or token in the script. The fleet configuration stores the script body
  and exposes it to anyone who can read the fleet. Stage the secret in S3 and reference it by URI
- Exceeding 15,000 characters, which makes the script impossible to apply to a fleet
