# Corona Add-on

Corona is a photorealistic rendering engine by Chaos that integrates as a plugin with 3ds Max.
It shares the same licensing structure as V-Ray.

## Reference Script

See `host_configuration_scripts/3dsmax/3dsmax-2025-and-corona-13.ps1` for a working example.

## CONFIG values

One optional value, holding the full S3 URI of the Corona installer. Blank skips Corona.

```powershell
$CORONA_S3_URI = ""  # e.g. s3://<bucket>/Corona_13_3dsmax_installer.exe
```

Derive the installer filename from the URI. Do not add a filename variable.

## What to add to the script

1. Add the `$CORONA_S3_URI` CONFIG value above, in the optional section
2. Start its download with the other downloads, gated on the URI being set
3. After installing 3ds Max, run the installer through `Invoke-WithErrorCapture` with `-gui=0 -auto`
4. Write the `vrlclient.xml` license file to `C:\Program Files\Common Files\ChaosGroup\`. The step needs
   elevated privileges, which the host config script already runs with
5. Set `VRAY_AUTH_CLIENT_FILE_PATH` to the directory, not the file itself

## Persistence

Where the script supports a persistent volume, add these junctions, gated on `$CORONA_S3_URI` being set:

```powershell
@{ Link = "C:\Program Files\Chaos Group"; Target = "$SW_PATH\ChaosGroup" }
@{ Link = "C:\Program Files\Common Files\ChaosGroup"; Target = "$SW_PATH\ChaosGroupCommon" }
```

The second junction carries `vrlclient.xml`, so licensing survives a reboot with the rest of the install.
If the script also installs V-Ray, add the `C:\Program Files\Chaos Group` junction only once.

## Important notes

- `VRAY_AUTH_CLIENT_FILE_PATH` must point to the directory `C:\Program Files\Common Files\ChaosGroup`, not
  to `vrlclient.xml` directly. Pointing it at the file is accepted at install time and fails at render
  time
- Corona uses the same `vrlclient.xml` licensing as V-Ray. If both are installed, only one copy of the
  file is needed
- Corona 14 is the first version to support 3ds Max 2027. Check vendor support before pairing a Corona
  version with a 3ds Max year
