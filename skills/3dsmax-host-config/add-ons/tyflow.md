# tyFlow Add-on

tyFlow is a particle system and physics simulation plugin for 3ds Max. It comes as a single
`.dlo` file, with no installer needed.

## Reference Script

See `host_configuration_scripts/3dsmax/3dsmax-2025-vray-and-tyflow.ps1` for a working example.

## CONFIG values

One optional value, holding the full S3 URI of the tyFlow `.dlo` file. Blank skips tyFlow.

```powershell
$TYFLOW_S3_URI = ""  # e.g. s3://<bucket>/tyFlow_1_1_1_2025.dlo
```

Derive the filename from the URI with `Split-Path -Leaf`. Do not add a filename variable, and do not add
a variable for the plugins directory, which comes from `$MAX_ROOT`.

## What to add to the script

1. Add the `$TYFLOW_S3_URI` CONFIG value above, in the optional section
2. Start its download with the other downloads, gated on the URI being set
3. After installing 3ds Max, copy the `.dlo` file into `$MAX_ROOT\plugins\`

```powershell
if ($tyflowDownload) {
    Wait-Download $tyflowDownload
    Copy-Item -Path $tyflowDownload.FilePath -Destination "$MAX_ROOT\plugins\" -Force
}
```

## Persistence

No junction of its own is needed. The `.dlo` file lands inside `$MAX_ROOT\plugins\`, which the base 3ds Max
junction already redirects onto the volume.

## Important notes

- No environment variables are needed. 3ds Max loads plugins automatically from the plugins directory
- The `.dlo` file name includes the 3ds Max year, so the file staged in S3 must match the version being
  installed. The script cannot detect a mismatch, because copying a `.dlo` built for another year succeeds
  and the plugin then fails to load at render time. Call out the requirement in the README rather than
  trying to validate it
- Because the copy always succeeds, log the destination path so the CloudWatch logs show what was placed
  where
