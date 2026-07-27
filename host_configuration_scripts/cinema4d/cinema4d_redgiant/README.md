# Host Configuration for Cinema 4D and Red Giant

This guide covers setting up the required software installers for the Red Giant host config script. You'll fetch the necessary standalone installers from Maxon and Microsoft, store them in S3, and then paste the provided `.ps1` script into your fleet's host configuration script so that it pulls each installer and runs it in silent mode on each Deadline Cloud worker launch. This solution has been tested and verified to work on Windows GPU SMF fleets only, but can also be applied to a CMF assuming your instance is a GPU Windows instance with the necessary driver installed to support GPU usage (not fully tested but theoretically should work).

> **⚠️ Performance Impact**: This script can add about **5-10 minutes** to worker launch time due to software installation. This number goes down as you vertically scale your instance size up. A g6.xlarge with 4 vCPUs + 16 GiB of memory adds 10 minutes while a g6.4xlarge with 16 vCPUs and 64 GiB memory adds 6 minutes. Plan around this for your fleet scaling and job scheduling. One strategy is to keep a warm worker alive during peak usage hours. If you have Cinema 4D jobs that don't require Red Giant, you can have one fleet for Cinema 4D renders via Conda and another fleet for Cinema 4D + Red Giant using this host configuration.

> **Faster subsequent boots are built in.** If a persistent volume is attached to the fleet, the script installs once to it and restores on later boots instead of reinstalling. See [Persistent Volumes (Automatic)](#persistent-volumes-automatic). No separate script or flag is needed.

## Prerequisites

- AWS CLI configured with appropriate permissions
- S3 bucket for storing installers (can use your job-attachments bucket)
- Red Giant licenses which are available on SMF and CMF via a [license endpoint](https://docs.aws.amazon.com/deadline-cloud/latest/developerguide/cmf-ubl.html)
- AWS Deadline Cloud farm, Windows GPU SMF (service-managed fleet) with latest driver, queue, and queue-fleet association set up. No need to add conda queue environment to your queue.

## Required Installers

*🔔 Note: the installer names can differ depending on the software versions, please keep note of differences so that the following script setup goes smoothly*

### 1. Red Giant

Download from Red Giant:
1. Log into your Maxon account
2. Navigate to the [Maxon Downloads](https://www.maxon.net/en/downloads) section
3. Download `RedGiant-2025.6.0-Win.exe` (or latest version) for Windows from the section Red Giant

Set `$RED_GIANT_S3_URI` in the script's CONFIG block to the full S3 URI of the Red Giant installer (format `s3://bucket/key.exe`, e.g., `s3://<your-installer-bucket>/RedGiant-2026.0.0-Win.exe`).

### 2. Maxon App

The Maxon App is needed to support Red Giant + Universe licensing, acting as a proxy between your licensing server and the plugins being run.
Download from Maxon:
1. Log into your Maxon account
2. Navigate to the [Maxon App](https://www.maxon.net/en/downloads) section after you scroll down a bit
3. Download `Maxon_App_2025.4.2_Win.exe` (or latest version) for Windows under the section Maxon App

Set `$MAXON_APP_S3_URI` to the full S3 URI of the Maxon App installer (format `s3://bucket/key.exe`).

### 3. Microsoft Edge WebView2 Runtime

The WebView2 Runtime is needed for the Maxon App installation to go smoothly. Download from Microsoft:
1. Visit the [Microsoft Edge WebView2 download page](https://developer.microsoft.com/en-us/microsoft-edge/webview2?form=MA13LH#download)
2. Download `MicrosoftEdgeWebView2RuntimeInstallerX64.exe` (x64 version) under the "Evergreen Standalone Installer" section

Set `$WEBVIEW2_S3_URI` to the full S3 URI of the WebView2 Runtime installer (format `s3://bucket/key.exe`).

## S3 Bucket Setup

### 1. Choose or Create an S3 Bucket

If you have a job attachments bucket, you can just go ahead and use that. If you want a separate bucket, go ahead and create one.

The script downloads each installer from the full S3 URI you set in its `CONFIG` block, so you're free to organize the objects however you like. Put them at the bucket root, under a shared prefix (e.g. `Installers/`), or in per-software folders. No folder structure is required. Whatever locations you choose, note down each object's full S3 URI (format `s3://bucket/key`), since you'll paste those URIs into the script config in the [Usage](#usage) step.

### 2. Upload Installers

Upload the `.exe` files to your bucket via the AWS S3 console, or programmatically. The examples below upload to the bucket root; if you prefer a prefix, append it to the destination (e.g. `s3://$INSTALLER_S3_BUCKET/Installers/`) and adjust your config URIs to match.

```bash
export INSTALLER_S3_BUCKET=your-installer-bucket

aws s3 cp "RedGiant-2025.6.0-Win.exe" s3://$INSTALLER_S3_BUCKET/
aws s3 cp "Maxon_App_2025.4.2_Win.exe" s3://$INSTALLER_S3_BUCKET/
aws s3 cp "MicrosoftEdgeWebView2RuntimeInstallerX64.exe" s3://$INSTALLER_S3_BUCKET/
```

### 3. Update IAM Role Permissions

Then, go to your Fleet role and add the following inline policy to that role. Scope the `Resource` to wherever you uploaded your installers: the whole bucket as shown below, or narrow it to a prefix (e.g. `arn:aws:s3:::<your bucket>/Installers/*`) if you grouped the objects under one:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Sid": "ReadBucket",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::<your bucket>/*"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:ResourceAccount": "<your aws account id>"
                }
            }
        }
    ]
}
```
The policy lets the host config script pull down the installers from your S3 bucket to install that software on your worker.

## Usage

### 1. Configure the Script

Before deploying, edit the `CONFIG` block at the top of the script. Set each variable to the full S3 URI (format `s3://bucket/key.exe`) of the corresponding installer you uploaded. All three are required, since Red Giant depends on the Maxon App and WebView2 Runtime:

```powershell
$RED_GIANT_S3_URI = "s3://<bucket>/RedGiant-2026.0.0-Win.exe"
$MAXON_APP_S3_URI = "s3://<bucket>/Maxon_App_2026.0.0_Win.exe"
$WEBVIEW2_S3_URI  = "s3://<bucket>/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
```

The script derives each installer's filename from its S3 URI, so there are no separate filename variables to keep in sync.

### 2. Add Host Config Script to Windows GPU Fleet

The contents of the script `.\install-software.ps1` belong in your Configuration Scripts for your fleet. To add it, go to Fleets and select your fleet. Under Configurations, paste your script into the Worker configuration script field. Then scroll down and set the script timeout to **900 seconds**. For more information, see the [AWS Deadline Cloud SMF administration guide](https://docs.aws.amazon.com/deadline-cloud/latest/developerguide/smf-admin.html).

## Persistent Volumes (Automatic)

If your fleet has a persistent volume configured, this script uses it automatically. Software installs once to the volume and subsequent boots restore in seconds instead of reinstalling. With no volume attached, it performs a normal install. No configuration is required.

To configure a persistent volume on your fleet, see the [Deadline Cloud persistent storage developer guide](https://docs.aws.amazon.com/deadline-cloud/latest/developerguide/smf-persistent-storage-dev.html) and [user guide](https://docs.aws.amazon.com/deadline-cloud/latest/userguide/volumes.html).

> **Sizing Tip**: Red Giant + Maxon App total ~5-10 GiB. 100 GiB is more than sufficient. The console default is 200 GiB.

## Local Installation

1. Install the Red Giant plugin by [following instructions here](https://support.maxon.net/hc/en-us/articles/212354258-How-do-I-install-my-products)
2. [Optional] Learn how to use Red Giant inside Cinema 4D with [this demonstration video](https://www.youtube.com/watch?v=L6B1REPQoPU)
3. Submit to Deadline Cloud from Cinema 4D by using menu command **Extensions > AWS Deadline Cloud Submitter**

## Local Dev Testing
To test the script locally, run PowerShell with Admin privileges on a Windows machine, add the credentials to your AWS account in the PowerShell window, and then run the following:

```powershell
# Run the automated installer
.\install-software.ps1
```

You might see failures on the WebView2 installation since your machine probably already has it, but you can splice that out and test the rest.

The script will:
1. Download all installers from S3 in parallel
2. Install Microsoft Edge WebView2 Runtime
3. Install Maxon App
4. Install Red Giant Suite

## Debugging

The script runs in strict mode (`$ErrorActionPreference = "Stop"`), so any unhandled error aborts it immediately rather than continuing in a bad state. Errors are never suppressed: a single trap near the top of the script writes the error message to the output stream, which is captured in the worker's CloudWatch Logs alongside the script's normal `Write-Host` progress output. Each installer runs through a helper that captures its stdout/stderr and, on a non-zero exit code, throws an error naming the failing installer and including its output. To diagnose a failure, open the worker's host-configuration log in CloudWatch and look for the `ERROR:` line and the last operation that printed before it.

## Troubleshooting

- Ensure all installer objects are present in S3 at the exact URIs you configured before running
- If your resulting renders are coming out corrupted on CMF, it's possible that you need to do Nvidia driver installation on your CMF to ensure that Red Giant is utilizing your GPU correctly
