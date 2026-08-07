# 3ds Max Host Config

This skill helps you generate a PowerShell host configuration script for any version of 3ds Max
and supported plugin combinations (V-Ray, Corona, tyFlow, Forest Pack, RailClone, and more) for
AWS Deadline Cloud Service Managed Fleet workers.

## How to use this skill with Kiro

### Prerequisites

- [Kiro](https://kiro.dev) installed
- This repository cloned and opened as a workspace in Kiro
- The 3ds Max installer (and any plugin installers) downloaded from the vendor and available locally
- An S3 bucket in the same region as your Deadline Cloud farm to host the installers

### Steps

1. Open Kiro chat
2. Tell Kiro what you need, such as:
   - `"Create a host configuration script for 3ds Max 2026"`
   - `"Create a host configuration script for 3ds Max 2026 and V-Ray 8"`
   - `"Add a host config script for 3ds Max 2027 with Forest Pack 10 and RailClone 7"`
3. Kiro generates the `.ps1` script for your version combination and adds a row describing it to the
   shared [3ds Max README](../../host_configuration_scripts/3dsmax/README.md)
4. Fill in the CONFIG block at the top of the script. Every editable value sits in that one block, and each
   carries its expected format inline. Each installer has its own full S3 URI variable (e.g.
   `$3DS_MAX_INSTALLER_ZIP_S3_URI="s3://your-bucket/path/to/installer.zip"`)
5. Upload your installers to your S3 bucket
6. Configure your Service Managed Fleet to use the generated script

### What the generated script does for you

The script follows the robustness standards shared by the host configuration samples in this repository:

- Validates your CONFIG values and downloads every installer before running any install, so a typo in an
  S3 URI fails in seconds instead of part way through a long install
- Captures installer output into CloudWatch, so a silent install that fails reports a reason rather than
  only an exit code
- Builds install paths from the 3ds Max version you set once, instead of repeating the year throughout,
  which is the usual source of breakage when bumping versions
- Detects a persistent volume automatically when your fleet attaches one, installing once and restoring on
  later boots. No configuration is needed to enable it
