# AEC Plugins Add-on

Common architectural visualization plugins for 3ds Max: Forest Pack and RailClone (by iToo Software),
and FloorGenerator and MultiTexture (by CG-Source). Use any combination as needed.

## Reference Script

See `host_configuration_scripts/3dsmax/3dsmax-2025-vray-and-aec-plugins.ps1` for a working example.

## CONFIG values

One optional value per plugin, each holding a full S3 URI. Blank skips that plugin, so an operator installs
only what they configure.

```powershell
$FOREST_PACK_S3_URI   = ""  # e.g. s3://<bucket>/forest_pack_pro_9_1_1_max2025.exe
$RAILCLONE_S3_URI     = ""  # e.g. s3://<bucket>/railclone_pro_7_1_1_max2025.exe
$FLOORGENERATOR_S3_URI = ""  # e.g. s3://<bucket>/FloorGenerator2.10_max2025.dlm
$MULTITEXTURE_S3_URI  = ""  # e.g. s3://<bucket>/MultiTexture2.11_max2025.dlt
```

Derive every filename from its URI. Derive the plugins directory and each `MAINDIR` from `$MAX_ROOT`
rather than exposing them as CONFIG values.

## What to add to the script

Include only the plugins being installed. Start all downloads together, then install sequentially, waiting
for each download immediately before its install.

**Forest Pack**

1. Add the `$FOREST_PACK_S3_URI` CONFIG value
2. Run the installer through `Invoke-WithErrorCapture` with `/S`, `MAXVER=max<year>-64`, `/MAXDIR`, and
   `/LICMODE=rendernode`, building `MAXVER` and `/MAXDIR` from `$MAX_VERSION` and `$MAX_ROOT`
3. Set `ITOO_SOFTWARE_FOREST_PACK_PRO_MAINDIR` and `ITOO_SOFTWARE_FOREST_PACK_PRO_USELICSERVER=0`

**RailClone**

1. Add the `$RAILCLONE_S3_URI` CONFIG value
2. Run the installer through `Invoke-WithErrorCapture` with `/S` and `/LICMODE=rendernode`
3. Set `ITOO_SOFTWARE_RAILCLONE_PRO_MAINDIR` and `ITOO_SOFTWARE_RAILCLONE_PRO_USELICSERVER=0`

**FloorGenerator and MultiTexture**

1. Add the `$FLOORGENERATOR_S3_URI` and `$MULTITEXTURE_S3_URI` CONFIG values
2. Copy each downloaded file into `$MAX_ROOT\plugins\`
3. No environment variables needed

## Persistence

Forest Pack and RailClone install under `C:\Program Files\ITooSoft`, so where the script supports a
persistent volume add this junction, gated on either URI being set:

```powershell
@{ Link = "C:\Program Files\ITooSoft"; Target = "$SW_PATH\ITooSoft" }
```

FloorGenerator and MultiTexture need no junction of their own. Both land inside `$MAX_ROOT\plugins\`, which
the base 3ds Max junction already covers.

## Important notes

- Forest Pack and RailClone: `/LICMODE=rendernode` installs without a UI license, which is required for
  fleet workers
- Forest Pack: `MAXVER` format is `max<year>-64` (e.g. `max2026-64`). Build it by interpolating
  `$MAX_VERSION` so it cannot drift from the installed version
- FloorGenerator and MultiTexture ship per 3ds Max year, so the files staged in S3 must match the version
  being installed. A mismatched file copies successfully and then fails to load at render time, so the
  script cannot catch it. State the requirement in the README
- Both `MAINDIR` values point at the 3ds Max install root, so derive them from `$MAX_ROOT` rather than
  restating the path
