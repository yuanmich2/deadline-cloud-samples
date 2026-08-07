# Host Config from Installer

This skill helps you create a host configuration script for software you want to run on AWS Deadline
Cloud Service Managed Fleet workers. It covers Windows `.exe` installers, which produce a PowerShell
script, and Linux installers or packages, which produce a Bash script.

Instead of writing the script manually, Kiro walks you through installing the software on your local
machine and verifying it works. It then uploads the installer to S3 and generates the script from the
steps that were confirmed working.

The generated script follows the robustness standards used by the reference host configuration scripts
in this repository:

- All editable values sit in one CONFIG block at the top of the script, each with its expected format,
  and the block is kept as small as possible
- Paths, installer filenames, and install directories are discovered at runtime rather than hardcoded,
  so the script survives a version bump
- Configuration is validated and installers downloaded before any install runs, so a bad value fails in
  seconds rather than after a long install
- Installer output is captured and sent to CloudWatch, so a failed unattended install reports why
- Secrets stay out of the script. Your fleet configuration stores the script body, so a license key or
  token belongs in your S3 bucket with only its URI in the script
- On Windows fleets with a persistent volume attached, the script installs once and restores on later
  boots instead of reinstalling

## How to use this skill with Kiro

### Prerequisites

- [Kiro](https://kiro.dev) installed
- This repository cloned and opened as a workspace in Kiro
- The installer file available locally, on the same platform your fleet runs
- AWS CLI installed and configured with credentials that have S3 access

### Steps

1. Open Kiro chat
2. Tell Kiro what you want to install:
   - `"I have a RealFlow 10 installer and I want to run it on my Deadline Cloud fleet"`
   - `"Help me create a host config script for Marvelous Designer 12"`
   - `"I want to install this .exe on my Service Managed Fleet workers"`
3. Kiro guides you step by step: it finds the silent install flags by testing them, verifies the install,
   uploads the installer to S3, then generates the script
4. At the end, review the generated script, fill in the CONFIG values at the top, and configure your
   fleet

### After generating

Set your fleet's minimum worker count to 1 and check the worker logs in the CloudWatch log group
`/aws/deadline/farm-<farm-id>/fleet-<fleet-id>` to confirm the script runs cleanly before you rely on it
in production. Host configuration changes apply only to workers launched after you save the update.

If you plan to use a persistent volume, reboot the worker after its first successful boot and confirm in
the logs that the second boot restored from the volume rather than reinstalling. A broken restore does not
break rendering, so nothing reports an error: the script simply reinstalls every boot and you lose the
startup time the volume was meant to save.
