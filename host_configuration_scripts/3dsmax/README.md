# 3ds Max host configuration scripts for AWS Deadline Cloud

These Windows host configuration scripts install 3ds Max, a renderer, and plugins onto AWS Deadline Cloud service-managed fleet workers. Each one downloads the installers you stage in your own S3 bucket, runs their silent installs, and sets up the Deadline Cloud adaptor. One `CONFIG` block at the top of the file is the only part you edit.

Installing 3ds Max needs administrative access to the worker, which a queue environment does not have. That is why this runs as a host configuration, executing as the worker boots and before it picks up any jobs.

## Choose a script

| Script | Installs |
|---|---|
| [3dsmax-vray.ps1](3dsmax-vray.ps1) | 3ds Max, V-Ray |
| [3dsmax-vray-tyflow-and-aec-plugins.ps1](3dsmax-vray-tyflow-and-aec-plugins.ps1) | 3ds Max, V-Ray, tyFlow, Forest Pack, RailClone, FloorGenerator, MultiTexture |
| [3dsmax-corona.ps1](3dsmax-corona.ps1) | 3ds Max, Corona |

Every script takes the 3ds Max year as a config value, so one file covers 2024 through 2027. Each plugin is individually optional, so any of these also works as a plain 3ds Max install if you leave the plugin values blank.

Pencil+ 4 has its own pair of scripts, each pinned to one 3ds Max release:

| Script | Installs |
|---|---|
| [3dsmax-2025-and-pencilplus-4.ps1](3dsmax-2025-and-pencilplus-4.ps1) | 3ds Max 2025, Pencil+ 4 |
| [3dsmax-2027-and-pencilplus-4.ps1](3dsmax-2027-and-pencilplus-4.ps1) | 3ds Max 2027, Pencil+ 4 |

Pencil+ renders watermark-free under `3dsmaxcmd.exe`, which runs as a render server, so the command-line render path needs no license server configuration. These two take `TODO` S3 URIs at the top of the file rather than a `CONFIG` block; the rest of the setup below applies unchanged.

## Set up

1. **Stage your installers in an S3 bucket**, in the same region as your farm. The 3ds Max installer needs repackaging first, because Autodesk ships a `.7z` plus an extractor and these scripts expect a `.zip`. See [Creating a 3ds Max installer archive in .zip format](#creating-a-3ds-max-installer-archive-in-zip-format).
2. **Grant the fleet's IAM role `s3:GetObject`** on those objects. Without it the worker cannot download anything, and the failure shows up only in the worker logs.
3. **Fill in the `CONFIG` block** at the top of your chosen script:
   - `$MAX_VERSION`, the 3ds Max year you are installing.
   - `$3DS_MAX_INSTALLER_ZIP_S3_URI`, the full S3 URI of the zip from step 1.
   - One URI per plugin you want. Leave the rest blank to skip them.
   - `$ADP_ANALYTICS_OPT_IN`, which 3ds Max 2027 requires. See [Known issues and workarounds](#known-issues-and-workarounds).
4. **Paste the script into the fleet's host configuration** and save.
5. **Verify on one worker first.** Set the fleet's minimum worker count to 1 and read the worker's CloudWatch logs at `/aws/deadline/farm-<farm-id>/fleet-<fleet-id>` to confirm every install step succeeded.
6. **Optional: Submit a test render** See [Testing](#testing). If the fleet uses a persistent volume, you may also want to confirm that persistent volume restores work too. See [Startup time and persistent volumes](#startup-time-and-persistent-volumes).

Host configuration changes only affect workers launched after you save. Existing workers keep running the old configuration.

## Creating a 3ds Max installer archive in .zip format

Autodesk distributes 3ds Max as a `.7z` archive plus an extraction executable. These scripts expect a ZIP so Windows can extract it without third-party software such as [7-Zip](https://www.7-zip.org/).

1. Open the [Autodesk Products and Services page](https://manage.autodesk.com/products), sign in, and choose **View details** for 3ds Max.
   <img width="1431" height="703" alt="Autodesk product details page" src="https://github.com/user-attachments/assets/b0df83ac-0eaa-431f-8216-763db29c5705" />
2. Select the version, open the menu beside **Download**, and choose **Direct Download**. Keep the downloaded `.7z` and `.exe` in the same folder.
   <img width="587" height="645" alt="Autodesk direct download menu" src="https://github.com/user-attachments/assets/32faf766-e26c-4dea-94ac-c8fde7dc8ccd" />
3. Run the `.exe`, wait for extraction, and choose **Open in folder**.
   <img width="514" height="154" alt="Autodesk extraction completion dialog" src="https://github.com/user-attachments/assets/42450f53-800f-4703-8b63-353bca2bed83" />
4. Select all extracted files and choose **Send to > Compressed (zipped) folder**.
   <img width="925" height="547" alt="Windows compressed folder menu" src="https://github.com/user-attachments/assets/48ba83fe-f1e8-4396-ac3b-ded1f10bf55f" />

## Testing

Because each script spans 3ds Max versions and plugin combinations rather than being pinned to one, the set of possible configurations is far wider than can be verified in advance. Any particular combination should be treated as unverified until it has produced a render. Silent-install options deserve the same scrutiny: each script hard-codes the unattended flags for its products, and vendors change those between releases, so a flag that no longer applies can leave an installer waiting on a prompt that nothing will answer.

[`examples/sunflower_sphere/`](examples/sunflower_sphere/) is a ready-to-submit job bundle that confirms a worker has 3ds Max and V-Ray configured correctly. Submit it with the [Deadline Cloud submitter](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/submitter.html) or the [Deadline Cloud client](https://pypi.org/project/deadline/), signing in through [Deadline Cloud monitor](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/monitor-onboarding.html) first so credentials are handled for you. From the `examples/sunflower_sphere/` directory:

```
deadline bundle gui-submit .    # with a GUI
deadline bundle submit .        # without
```

A successful render produces a sphere with a sunflower texture, downloadable from the monitor once the job completes. For plugin combinations the bundle does not cover, render something that exercises those plugins specifically.

## Known issues and workarounds

**3ds Max 2027 requires opting in to the Autodesk Analytics Program.** ADP is Autodesk's usage-data collection program. On 2027, a render node whose user is opted out aborts during startup with exit code `-12`, so no renders complete. Setting `$ADP_ANALYTICS_OPT_IN` to `$true` records that consent on the worker and lets 2027 start normally. The flag has no effect on other versions, and it defaults to off because accepting an analytics agreement belongs to the studio rather than to a script.

Explicitly opting out does not avoid the failure, which is the counterintuitive part. A recorded refusal leaves 2027 failing in the same way, so opting in is the only available workaround. See [deadline-cloud-for-3ds-max discussion #271](https://github.com/aws-deadline/deadline-cloud-for-3ds-max/discussions/271) for the investigation behind this.

The Pencil+ 2027 script has no equivalent flag, so a fleet built on it needs the consent recorded by other means before 2027 workers will render.

**The V-Ray installer must keep its original filename.** It can fail silently if renamed after download from Chaos.

**Host configuration scripts are capped at 15,000 characters**, counted after the `CONFIG` block is filled in. Long bucket names and deep key prefixes can push a script past the limit, and the fleet rejects it on save. Shortening the S3 keys, or deleting the `# e.g.` comment beside each populated URI, recovers the room.

## Startup time and persistent volumes

A full run of these scripts takes several minutes, and it repeats on every worker launch. Enabling a persistent volume on the fleet reduces that substantially. The scripts detect the volume automatically with no change to the `CONFIG` block: the first worker installs onto it, and later workers restore from it instead of reinstalling.

A failed restore is invisible from the outside, because the script falls back to a full reinstall and renders still succeed. Slow startups are the only symptom, which makes the restore path worth confirming once after enabling a volume.

Workers cannot be rebooted on demand, so verifying it takes two launches:

1. Submit a job to bring up a worker, and note how long the host configuration takes in that worker's CloudWatch log.
2. Cancel the job and wait for the worker to shut itself down.
3. Submit another job. The second worker should finish its host configuration substantially faster, and its log should show a restore rather than a full install.

Raising the fleet's minimum worker count above zero also brings up workers without submitting a job. Reset it to zero afterwards, or the fleet keeps idle workers running and billing.

## Generate a script for another combination with Kiro

Changing the 3ds Max version needs no new script, only a different `$MAX_VERSION`. For a renderer or plugin these scripts do not cover, you can use [Kiro](https://kiro.dev) with this repository. Install Kiro, clone this repository, open it as the workspace, and ask for what you need:

* `Create a host configuration script for 3ds Max and Arnold`
* `Add Phoenix FD to the V-Ray host configuration script`
* `Update the V-Ray host configuration script for a newer V-Ray release`

Kiro reads [`skills/3dsmax-host-config/SKILL.md`](../../skills/3dsmax-host-config/SKILL.md) and generates a `.ps1` in this directory. Review and test the result, fill in its `CONFIG` block, and check the character count before configuring a fleet.
