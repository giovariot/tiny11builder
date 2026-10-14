<#
.SYNOPSIS
    tiny11maker in-place maintenance ("post-update cleanup").

.DESCRIPTION
    Re-applies the tiny11maker trimming to an ALREADY INSTALLED Windows 11.

    Run it inside the running VM AFTER Windows Update. It will:
      * remove the bloat / AI apps that Windows Update re-provisioned or
        re-installed in the user profiles;
      * remove the optional language features (Handwriting, OCR, Speech,
        TextToSpeech) again, if Windows brought them back;
      * re-apply the AI / privacy / telemetry registry policies;
      * disable the telemetry services and scheduled tasks again;
      * reclaim disk space with DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase.

    It never touches Windows Defender and it does NOT try to rebuild WinSxS
    (that is only possible offline). It is safe to run repeatedly.

.NOTES
    Author: tiny11builder (fork)
    Run as Administrator, online, in a normal Windows session.
#>

#---------[ Functions ]---------#
function Set-RegistryValue {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )
    try {
        & 'reg' 'add' $path '/v' $name '/t' $type '/d' $value '/f' | Out-Null
    } catch {
        Write-Host "  Error setting ${path}\${name}: $_"
    }
}

function Remove-RegistryValue {
    param (
        [string]$path
    )
    & 'reg' 'delete' $path '/f' 2>&1 | Out-Null
}

function Set-ServiceStartupType {
    param (
        [string]$service,
        [int]$start = 4
    )
    & 'reg' 'add' "HKLM\SYSTEM\CurrentControlSet\Services\$service" '/v' 'Start' '/t' 'REG_DWORD' '/d' "$start" '/f' | Out-Null
    if ($start -eq 4) {
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
    }
}

#---------[ Execution ]---------#

# Check if PowerShell execution is restricted
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "Your current PowerShell Execution Policy is set to Restricted, which prevents scripts from running. Do you want to change it to RemoteSigned? (yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Host "The script cannot be run without changing the execution policy. Exiting..."
        exit
    }
}

# Elevate if not running as Administrator
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
if (! $myWindowsPrincipal.IsInRole($adminRole)) {
    Write-Host "Restarting tiny11 in-place maintenance as admin in a new window, you can close this one."
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

Start-Transcript -Path "$PSScriptRoot\tiny11maker-inplace_$(Get-Date -f yyyyMMdd_HHmmss).log" | Out-Null
Clear-Host
Write-Host "Welcome to tiny11 in-place maintenance! This script re-cleans an installed tiny11 image."

# Hives are touched live, so make sure we are not fighting a pending reboot forever.
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    Write-Host "WARNING: a reboot is pending. For best results reboot first, then run this script again."
}

# Appx packages that tiny11maker removes. Matching is "contains", like the maker.
$bloatPrefixes = 'AppUp.IntelManagementandSecurityStatus',
'Clipchamp.Clipchamp',
'DolbyLaboratories.DolbyAccess',
'DolbyLaboratories.DolbyDigitalPlusDecoderOEM',
'Microsoft.BingNews',
'Microsoft.BingSearch',
'Microsoft.BingWeather',
'Microsoft.Copilot',
'Microsoft.Windows.CrossDevice',
'Microsoft.GamingApp',
'Microsoft.GetHelp',
'Microsoft.Getstarted',
'Microsoft.Microsoft3DViewer',
'Microsoft.MicrosoftOfficeHub',
'Microsoft.MicrosoftSolitaireCollection',
'Microsoft.MicrosoftStickyNotes',
'Microsoft.MixedReality.Portal',
'Microsoft.MSPaint',
'Microsoft.Office.OneNote',
'Microsoft.OfficePushNotificationUtility',
'Microsoft.OutlookForWindows',
'Microsoft.Paint',
'Microsoft.People',
'Microsoft.PowerAutomateDesktop',
'Microsoft.SkypeApp',
'Microsoft.StartExperiencesApp',
'Microsoft.Todos',
'Microsoft.Wallet',
'Microsoft.Windows.DevHome',
'Microsoft.Windows.Copilot',
'Microsoft.Windows.Teams',
'Microsoft.WindowsAlarms',
'Microsoft.WindowsCamera',
'microsoft.windowscommunicationsapps',
'Microsoft.WindowsFeedbackHub',
'Microsoft.WindowsMaps',
'Microsoft.WindowsSoundRecorder',
'Microsoft.WindowsTerminal',
'Microsoft.Xbox.TCUI',
'Microsoft.XboxApp',
'Microsoft.XboxGameOverlay',
'Microsoft.XboxGamingOverlay',
'Microsoft.XboxIdentityProvider',
'Microsoft.XboxSpeechToTextOverlay',
'Microsoft.YourPhone',
'Microsoft.ZuneMusic',
'Microsoft.ZuneVideo',
'MicrosoftCorporationII.MicrosoftFamily',
'MicrosoftCorporationII.QuickAssist',
'MSTeams',
'MicrosoftTeams',
'Microsoft.549981C3F5F10',
# --- AI / Copilot / privacy additions ---
'Microsoft.Windows.Ai.Copilot',
'Microsoft.Windows.Ai.Copilot.Provider',
'Microsoft.CopilotPlus',
'Microsoft.Windows.CopilotPlus',
'MicrosoftWindows.Client.WebExperience',
'Microsoft.WidgetsPlatformRuntime',
'Microsoft.Windows.Widgets'

function Test-BloatPackage {
    param ([string]$Name)
    return (($bloatPrefixes | Where-Object { $Name -like "*$_*" }).Count -gt 0)
}

Write-Host "Removing provisioned apps that Windows Update reinstalled..."
$provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
foreach ($app in $provisioned) {
    if (Test-BloatPackage $app.PackageName) {
        Write-Host "  Removing provisioned $($app.PackageName)"
        Remove-AppxProvisionedPackage -Online -PackageName $app.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Host "Removing installed apps for all users..."
$installed = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
foreach ($app in $installed) {
    if (Test-BloatPackage $app.Name) {
        Write-Host "  Removing $($app.Name)"
        Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------
# Microsoft Edge removal (best effort, unsupported by Microsoft).
# The offline builder deletes Edge from the image; online we uninstall it
# with its own setup and then block EdgeUpdate from reinstalling it.
# WebView2 is removed as well, to match what the offline builder does
# (some WebView2-based apps may stop working: that is expected here).
# ---------------------------------------------------------------
Write-Host "Removing Microsoft Edge (best effort)..."
Get-Process msedge, msedgewebview2 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$edgeApplicationDirs = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application",
    "$env:ProgramFiles\Microsoft\Edge\Application"
)
foreach ($edgeAppDir in $edgeApplicationDirs) {
    if (Test-Path $edgeAppDir) {
        Get-ChildItem -Path $edgeAppDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $edgeSetup = Join-Path $_.FullName "Installer\setup.exe"
            if (Test-Path $edgeSetup) {
                Write-Host "  Uninstalling Edge $($_.Name)..."
                Start-Process -FilePath $edgeSetup -ArgumentList "--uninstall","--system-level","--verbose-logging","--force-uninstall" -Wait -ErrorAction SilentlyContinue
            }
        }
    }
}

# Remove the Edge appx (Stable) if present.
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.PackageName -like "*MicrosoftEdge*" } |
    ForEach-Object {
        Write-Host "  Removing provisioned $($_.PackageName)"
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "*MicrosoftEdge*" } |
    ForEach-Object {
        Write-Host "  Removing $($_.Name)"
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }

# Leftovers: Edge, EdgeUpdate, EdgeCore and WebView2.
$edgePathsToRemove = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeCore",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView",
    "$env:ProgramFiles\Microsoft\Edge",
    "$env:ProgramFiles\Microsoft\EdgeCore",
    "$env:ProgramFiles\Microsoft\EdgeUpdate",
    "$env:ProgramFiles\Microsoft\EdgeWebView",
    "$env:SystemRoot\System32\Microsoft-Edge-Webview"
)
foreach ($edgePath in $edgePathsToRemove) {
    if (Test-Path $edgePath) {
        Write-Host "  Removing $edgePath"
        Remove-Item -Path $edgePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Edge shortcuts and EdgeUpdate scheduled tasks.
foreach ($edgeShortcut in @("$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk")) {
    Remove-Item -Path $edgeShortcut -Force -ErrorAction SilentlyContinue
}
Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -like "*Edge*" } |
    ForEach-Object {
        Write-Host "  Removing scheduled task $($_.TaskName)"
        Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    }

# Block Edge/WebView2 from being reinstalled or updated again.
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'InstallDefault' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'UpdateDefault' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
Remove-RegistryValue 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update'

# ---------------------------------------------------------------
# OneDrive removal (best effort).
# ---------------------------------------------------------------
Write-Host "Removing OneDrive (best effort)..."
Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$oneDriveSetups = @(
    "$env:SystemRoot\System32\OneDriveSetup.exe",
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
)
$oneDriveSetups += (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive" -Filter "OneDriveSetup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
foreach ($oneDriveSetup in $oneDriveSetups) {
    if ($oneDriveSetup -and (Test-Path $oneDriveSetup)) {
        Write-Host "  Running $oneDriveSetup /uninstall"
        Start-Process -FilePath $oneDriveSetup -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
    }
}

$oneDrivePathsToRemove = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:ProgramData\Microsoft OneDrive",
    "$env:ProgramFiles\Microsoft OneDrive",
    "${env:ProgramFiles(x86)}\Microsoft OneDrive",
    "$env:SystemRoot\System32\OneDriveSetup.exe"
)
foreach ($oneDrivePath in $oneDrivePathsToRemove) {
    if (Test-Path $oneDrivePath) {
        Write-Host "  Removing $oneDrivePath"
        Remove-Item -Path $oneDrivePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Remove-RegistryValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe'
Remove-RegistryValue 'HKCU\Software\Microsoft\OneDrive'
& 'reg' 'delete' 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' '/v' 'OneDrive' '/f' 2>&1 | Out-Null
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSync' 'REG_DWORD' '1'

Write-Host "Removing language features (Handwriting, OCR, Speech, TextToSpeech)..."
$languageCode = (Get-WinSystemLocale).Name
if (-not $languageCode) { $languageCode = "en-US" }
Write-Host "  Target language: $languageCode"
$languagePackagePatterns = @(
    "Microsoft-Windows-LanguageFeatures-Handwriting-$languageCode-Package~",
    "Microsoft-Windows-LanguageFeatures-OCR-$languageCode-Package~",
    "Microsoft-Windows-LanguageFeatures-Speech-$languageCode-Package~",
    "Microsoft-Windows-LanguageFeatures-TextToSpeech-$languageCode-Package~"
)
$allPackages = & dism /Online /English /Get-Packages /Format:Table
$allPackages = $allPackages -split "`n" | Select-Object -Skip 1
foreach ($packagePattern in $languagePackagePatterns) {
    $languagePackages = $allPackages | Where-Object { $_ -like "$packagePattern*" }
    foreach ($languagePackage in $languagePackages) {
        $languagePackageIdentity = ($languagePackage -split "\s+")[0]
        Write-Host "  Removing $languagePackageIdentity..."
        & dism /Online /English /Remove-Package /PackageName:$languagePackageIdentity 2>&1 | Out-Null
    }
}

Write-Host "Re-applying AI / privacy registry policies..."
# Windows AI (device + current user)
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallExport' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableSettingsAgent' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'RemoveMicrosoftCopilotApp' 'REG_DWORD' '1'
Set-RegistryValue 'HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 'REG_DWORD' '1'
Set-RegistryValue 'HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 'REG_DWORD' '1'
# Paint AI
Set-RegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableCocreator' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableGenerativeFill' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableImageCreator' 'REG_DWORD' '1'
# Notepad AI
Set-RegistryValue 'HKLM\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 'REG_DWORD' '1'
# Copilot + Edge Copilot
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
Set-RegistryValue 'HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'CopilotPageContext' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'CopilotCDPPageContext' 'REG_DWORD' '0'

Write-Host "Re-applying telemetry / activity history / search policies..."
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDiagnosticLogCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDumpCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 'REG_DWORD' '1'
Set-RegistryValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowSearchToUseLocation' 'REG_DWORD' '0'
Set-RegistryValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'

Write-Host "Re-disabling telemetry / diagnostics services..."
Set-ServiceStartupType 'DiagTrack'
Set-ServiceStartupType 'dmwappushservice'
Set-ServiceStartupType 'diagnosticshub.standardcollector.service'
Set-ServiceStartupType 'DPS'
Set-ServiceStartupType 'WdiServiceHost'
Set-ServiceStartupType 'WdiSystemHost'
Set-ServiceStartupType 'WerSvc'
Set-ServiceStartupType 'PcaSvc'

Write-Host "Re-applying disk space tweaks..."
Set-RegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabledDefault' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' 'CrashDumpEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' 'DisableSR' 'REG_DWORD' '1'
Set-ServiceStartupType 'SysMain'

Write-Host "Re-disabling telemetry scheduled tasks..."
$tasksToDisable = @(
    "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "Microsoft\Windows\Chkdsk\Proxy",
    "Microsoft\Windows\Windows Error Reporting\QueueReporting",
    "Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
    "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
)
foreach ($task in $tasksToDisable) {
    & schtasks /Change /TN "$task" /Disable 2>&1 | Out-Null
}

Write-Host "Removing the hibernation file if present..."
& powercfg /hibernate off 2>&1 | Out-Null

Write-Host "Running component cleanup with /ResetBase. This can take a long time..."
& dism /Online /English /Cleanup-Image /StartComponentCleanup /ResetBase

Write-Host ""
Write-Host "In-place maintenance completed."
Write-Host "A reboot is recommended to apply the scheduled task/service changes."
Read-Host "Press Enter to close"

Stop-Transcript
