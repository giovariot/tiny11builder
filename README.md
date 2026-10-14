# tiny11builder
*Scripts to build a trimmed-down Windows 11 image - now in **PowerShell**!*

## Introduction :
Tiny11 builder, now completely overhauled. <br> After more than a year (for which I am so sorry) of no updates, tiny11 builder is now a much more complete and flexible solution - one script fits all. Also, it is a steppingstone for an even more fleshed-out solution.

You can now use it on ANY Windows 11 release (not just a specific build), as well as ANY language or architecture.
This is made possible thanks to the much-improved scripting capabilities of PowerShell, compared to the older Batch release.

This is a script created to automate the build of a streamlined Windows 11 image, similar to tiny10.
The script has also been updated to use DISM's recovery compression, resulting in a much smaller final ISO size, and no utilities from external sources. The only other executable included is **oscdimg.exe**, which is provided in the Windows ADK and it is used to create bootable ISO images. 
Also included is an unattended answer file, which is used to bypass the Microsoft Account on OOBE and to deploy the image with the `/compact` flag.
It's open-source, **so feel free to add or remove anything you want!** Feedback is also much appreciated.

Also, for the very first time, **introducing tiny11 core builder**! A more powerful script, designed for a quick and dirty development testbed. Just the bare minimum, none of the fluff. 
This script generates a significantly reduced Windows 11 image. However, **it's not suitable for regular use due to its lack of serviceability - you can't add languages, updates, or features post-creation**. tiny11 Core is not a full Windows 11 substitute but a rapid testing or development tool, potentially useful for VM environments.

---

## ⚠️ Script versions:
- **tiny11maker.ps1** : The regular script, which removes a lot of bloat but keeps the system serviceable. You can add languages, updates, and features post-creation. This is the recommended script for regular use. It now also removes the optional language features (Handwriting, OCR, Speech, TextToSpeech) while keeping Windows Defender enabled.
- ⚠️ **tiny11coremaker.ps1** : The core script, which removes even more bloat but also removes the ability to service the image. You cannot add languages, updates, or features post-creation. This is recommended for quick testing or development use.
- 🧹 **tiny11maker-inplace.ps1** : A maintenance script to run **inside an already installed tiny11maker system, after Windows Update**. It removes the bloat/AI apps that updates reinstall, removes the language features again if they come back, removes **Edge and OneDrive** (best effort) and blocks Edge from being reinstalled, re-applies the AI/privacy policies and reclaims space with `DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase`. It does not touch Defender and does not rebuild WinSxS (only possible offline). Safe to run periodically.

## Instructions:
1. Download Windows 11 from the [Microsoft website](https://www.microsoft.com/software-download/windows11) or [Rufus](https://github.com/pbatard/rufus)
2. Mount the downloaded ISO image using Windows Explorer.
3. Open **PowerShell 5.1** as Administrator. 
5. Change the script execution policy :
```powershell
Set-ExecutionPolicy Bypass -Scope Process
```
> Using `-Scope Process` you keep your original policy intact as this change only lasts for the current PowerShell session. 

6. Start the script :
```powershell
C:/path/to/your/tiny11/script.ps1 -ISO <letter> -SCRATCH <letter>
``` 
> You can see of the script by running the `get-help` command.

6. Select the drive letter where the image is mounted (only the letter, no colon (:))
7. Select the SKU that you want the image to be based.
8. Sit back and relax :)
9. When the image is completed, you will see it in the folder where the script was extracted, with the name tiny11.iso

---

## What is removed:
<table>
  <tbody>
    <tr>
      <th>Tiny11maker</th>
      <th>Tiny11coremaker</th>
    </tr>
    <tr>
      <td>
        <ul>
          <li>Clipchamp</li>
          <li>News</li>
          <li>Weather</li>
          <li>Xbox</li>
          <li>GetHelp</li>
          <li>GetStarted</li>
          <li>Office Hub</li>
          <li>Solitaire</li>
          <li>PeopleApp</li>
          <li>PowerAutomate</li>
          <li>ToDo</li>
          <li>Alarms</li>
          <li>Mail and Calendar</li>
          <li>Feedback Hub</li>
          <li>Maps</li>
          <li>Sound Recorder</li>
          <li>Your Phone</li>
          <li>Media Player</li>
          <li>QuickAssist</li>
          <li>Internet Explorer</li>
          <li>Tablet PC Math</li>
          <li>Edge</li>
          <li>OneDrive</li>
          <li>Language features (Handwriting, OCR, Speech, TextToSpeech)</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>all from regular tiny +</li>
          <li>Windows Component Store (WinSxS)</li>
          <li>Windows Defender (only disabled, can be enabled back if needed)</li>
          <li>Windows Update (wouldn't work without WinSxS, enabling it would put the system in a state of failure)</li>
          <li>WinRE</li>
        </ul>
      </td>
    </tr>
  </tbody>
</table>

### AI, privacy and telemetry hardening (both scripts)

Beyond the classic bloat, both scripts now also remove or disable the newer
Windows "AI" and data-collection features:

- **Removed apps**: Copilot / Copilot+ providers, Windows Web Experience Pack
  (Widgets), Phone Link / Cross Device, Start experiences, Bing search in the
  Start menu, Dev Home, Outlook (new) and Teams.
- **AI features disabled by policy** (registry, works even when the app is kept):
  Recall and snapshot saving (`DisableAIDataAnalysis`, `AllowRecallEnablement`),
  Click to Do (`DisableClickToDo`), Settings agentic search
  (`DisableSettingsAgent`), Paint Cocreator / generative fill / image creator,
  Notepad AI (`DisableAIFeatures`) and Windows Copilot.
- **Recall component removed** in tiny11 Core (`/Disable-Feature /FeatureName:Recall /Remove`).
- **Hidden data collection turned off**: diagnostic data, advertising ID,
  activity history / timeline, error reporting / CEIP, customer feedback and
  the telemetry services (`DiagTrack`, `dmwappushservice`, `DPS`,
  `WdiServiceHost`, `WdiSystemHost`, `WerSvc`, `PcaSvc`).
- **Web results disabled** in Start / search and Cortana.

### Optimized for virtual machines (Apple Silicon / Arm64)

The scripts default to a configuration that is lean on disk, which is handy for
VMs (Parallels, VMware Fusion, UTM) on Apple Silicon Macs:

- Hibernation is disabled (no multi-GB `hiberfil.sys`).
- Kernel crash dumps are disabled.
- System Restore / Shadow Copies are disabled.
- `SysMain` (Superfetch) is disabled to reduce background disk I/O.
- The unattended file is rewritten to the detected architecture
  (`amd64`/`arm64`), so the `Compact` install and OOBE bypass apply on Arm too.

> Note for Arm64: tiny11 Core previously had several bugs that broke the Arm
> path: `$ScratchDisk` was never assigned (so registry loading, the WinSxS
> rebuild and the ISO creation all failed), the arm64 WinSxS copy list was
> missing its commas, the arm64 Edge WebView cleanup redirected the folder list
> into a file instead of a variable, and `autounattend.xml` was never placed at
> the root of the ISO. All of these are fixed here.

### Post-update cleanup (tiny11maker, online)

Windows Update periodically reinstalls some of the apps and features that
tiny11maker removed (this is the "ongoing battle" mentioned in *Known issues*).
`tiny11maker-inplace.ps1` re-applies the trimming to a running installation:

1. Boot the VM and open **PowerShell 5.1 as Administrator**.
2. `Set-ExecutionPolicy Bypass -Scope Process`
3. `C:/path/to/tiny11maker-inplace.ps1`

It removes provisioned and installed bloat/AI apps, removes the language
features again if they came back, uninstalls **Microsoft Edge** with its own
`setup.exe --uninstall --system-level --force-uninstall` and removes **OneDrive**
(best effort), blocks EdgeUpdate from reinstalling Edge/WebView2, re-applies the
privacy/AI policies and the disk-space tweaks, disables the telemetry
services/tasks and finishes with
`DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase`.

Limits: Edge removal is **best effort and unsupported by Microsoft** (Windows
Update may bring it back — just run the script again), and it cannot rebuild
WinSxS (that only works on a mounted image). Reboot when it finishes.

Keep in mind that **you cannot add back features in tiny11 core**! <br>
You will be asked during image creation if you want to enable .net 3.5 support!

---

## Known issues:
- Although Edge is removed, there are some remnants in the Settings, but the app in itself is deleted. 
- You might have to update Winget before being able to install any apps, using Microsoft Store.
- Outlook and Dev Home might reappear after some time. This is an ongoing battle, though the latest script update tries to prevent this more aggressively.
- If you are using this script on arm64, you might see a glimpse of an error while running the script. This is caused by the fact that the arm64 image doesn't have OneDriveSetup.exe included in the System32 folder.
- Do **not** run the **build** scripts (`tiny11maker`/`tiny11coremaker`) from a network/UNC path (for example a Parallels/macOS shared folder like `\\Mac\...`): they write very large files (mounted image, WIM, ISO), so use the guest's local disk (e.g. `C:\tiny11builder-release`). The in-place script can be run from the share. Self-elevation now passes `-ExecutionPolicy Bypass`, so a script on a UNC path is no longer blocked.
- During image export DISM can fail with **Error 8 (not enough memory)** on machines with little RAM. The scripts now retry with `/Compress:max` and, if that fails too, **keep the modified `install.wim`** (it already contains all the tiny11 changes) instead of deleting it: the ISO is still a trimmed tiny11, just a bit larger, instead of ending up ~0.9 GB and image-less. Before writing the ISO they also check that the install image exists/looks valid and that there is enough free space on the output drive, and they verify the `oscdimg` result; otherwise they stop with a clear error. For the smallest ISO, give the build machine **8+ GB RAM (12–16 GB recommended)** and ~50 GB of free disk.

---

## Features to be implemented:
- ~~disabling telemetry~~ (Implemented in the 04-29-24 release!)
- ~~more ad suppression~~ (Partially implemented in the 09-06-25 release!)
- improved language and arch detection
- more flexibility in what to keep and what to delete
- maybe a GUI???

And that's pretty much it for now!
## ❤️ Support the Project

If this project has helped you, please consider showing your support! A small donation helps me dedicate more time to projects like this.
Thank you!

**[Patreon](http://patreon.com/ntdev) | [PayPal](http://paypal.me/ntdev2) | [Ko-fi](http://ko-fi.com/ntdev)**
Thanks for trying it and let me know how you like it!
