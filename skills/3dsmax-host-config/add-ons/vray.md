# V-Ray Add-on

V-Ray is a professional rendering engine by Chaos Group that integrates as a plugin with 3ds Max.

## Reference Script

See `host_configuration_scripts/3dsmax/3dsmax-2025-and-vray.ps1` for a working example.

## CONFIG values

One optional value, holding the full S3 URI of the V-Ray installer. Blank skips V-Ray.

```powershell
$VRAY_S3_URI = ""  # e.g. s3://<bucket>/vray_adv_70020_max_x64.exe
```

Do not add a separate variable for the installer filename or the install root. Derive the filename from
the URI, and derive the install root from `$MAX_VERSION`:

```powershell
$VRAY_ROOT = "C:\ProgramData\Autodesk\ApplicationPlugins\VRay3dsMax$MAX_VERSION"
```

## What to add to the script

1. Add the `$VRAY_S3_URI` CONFIG value above, in the optional section
2. Start its download with the other downloads, gated on the URI being set
3. After installing 3ds Max, write the silent install config XML to `C:\3dsmax_setup\config.xml`, then run
   the installer through `Invoke-WithErrorCapture` with `-gui=0 -configFile -quiet=1`
4. Run `setvrlservice.exe -cloud-server=0` from the V-Ray `utils` directory (see Cloud Licensing below)
5. Set three environment variables, all suffixed with the 3ds Max year, built by interpolating
   `$MAX_VERSION` rather than writing the year as a literal:
   - `VRAY_FOR_3DSMAX<year>_MAIN`
   - `VRAY_FOR_3DSMAX<year>_PLUGINS`
   - `VRAY_MDL_PATH_3DSMAX<year>`, derived from the install root

## Silent install config XML

The config file sets telemetry off and enables remote licensing, which render nodes require:

```xml
<Value Name="ANONYMOUS_TELEMETRY" DataType="value">0</Value>
<Value Name="PERSONALIZED_TELEMETRY" DataType="value">0</Value>
<Value Name="REMOTE_LICENSE" DataType="value">1</Value>
```

## Cloud Licensing

V-Ray 7.30.02 and later enable Chaos Cloud Licensing by default, which breaks Usage Based Licensing on
fleet workers. Every V-Ray script in this repository disables it after install:

```powershell
Start-Process "$VRAY_ROOT\utils\setvrlservice.exe" -ArgumentList '-cloud-server=0' -Wait
```

Leaving Cloud Licensing enabled produces workers that install correctly and then fail to acquire a
license at render time, which is hard to diagnose from the install logs alone.

The existing scripts append `-ErrorAction SilentlyContinue` to this call. Prefer checking the path first
and warning if it is absent, so a missing utility is visible in the logs rather than silently skipped:

```powershell
if (Test-Path "$VRAY_ROOT\utils\setvrlservice.exe") {
    Invoke-WithErrorCapture "$VRAY_ROOT\utils\setvrlservice.exe" "-cloud-server=0"
} else {
    Write-Host "WARNING: setvrlservice.exe not found under $VRAY_ROOT\utils - Cloud Licensing not disabled"
}
```

## Persistence

Where the script supports a persistent volume, add this junction, gated on `$VRAY_S3_URI` being set:

```powershell
@{ Link = "C:\Program Files\Chaos Group"; Target = "$SW_PATH\ChaosGroup" }
```

The V-Ray plugin directory under `C:\ProgramData\Autodesk\ApplicationPlugins` is covered by the
`C:\ProgramData\Autodesk` junction the base 3ds Max install already creates, so it needs no entry of its
own.

## Important notes

- Do not rename the V-Ray installer executable. It can fail silently when renamed after download from
  Chaos
- The year suffix in the V-Ray env var names MUST match the 3ds Max version year. Interpolating
  `$MAX_VERSION` into the names prevents the mismatch, which is the most common mistake when bumping
  versions
- Derive the MDL path from the install root rather than exposing it as a separate CONFIG value
