<#
.SYNOPSIS
    Export Intune-related event logs **and** Intune Management Extension logs
    into one ZIP, with no interactive prompts.
.PARAMETER IncludeDebug
    Add the Analytic/Debug event-log channel (enabled quietly if needed).
.NOTES
    Run from an *elevated* PowerShell session.
#>

param(
    [switch]$IncludeDebug
)

$ConfirmPreference = 'None'   # silence PowerShell-side confirmations

# ── Event-log channels ────────────────────────────────────────────────────────
$LogChannels = @(
    'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin',
    'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational',
    'Microsoft-Windows-User Device Registration/Admin',
    'Microsoft-Windows-ModernDeployment-Diagnostics-Provider/Autopilot',
    'Microsoft-Windows-TaskScheduler/Operational'
)
if ($IncludeDebug) {
    $LogChannels += 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Debug'
}

# ── Paths ─────────────────────────────────────────────────────────────────────
$OutDir     = 'C:\IntuneLogs'                                   # master folder
$IMEsrcPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'  # IME logs
$IMEdstPath = Join-Path $OutDir 'IME'                           # sub-folder for IME
$ZipPath    = Join-Path $OutDir 'Intune_Logs.zip'               # zip file (overwritten)

New-Item -Path $OutDir   -ItemType Directory -Force | Out-Null
New-Item -Path $IMEdstPath -ItemType Directory -Force | Out-Null

# ── Helper: enable a log silently (handles Analytic/Debug prompt) ─────────────
function Enable-LogSilently {
    param(
        [string]$Channel,
        [switch]$IsDebug
    )
    try {
        $log = Get-WinEvent -ListLog $Channel -ErrorAction Stop
        if (-not $log.IsEnabled) {
            if ($IsDebug) {
                wevtutil sl "$Channel" /e:true /q:true  # suppress Y/N prompt
            }
            else {
                wevtutil sl "$Channel" /e:true
            }
            Write-Verbose "Enabled $Channel"
        }
    }
    catch {
        Write-Warning "Cannot query or enable '$Channel' — $_"
    }
}

# ── Export event logs ─────────────────────────────────────────────────────────
foreach ($Channel in $LogChannels) {

    $IsDebug = $Channel -like '*/Debug'
    if ($IsDebug) { Enable-LogSilently -Channel $Channel -IsDebug }

    $SafeName = ($Channel -replace '[\\\/]', '_') + '.evtx'
    $OutFile  = Join-Path $OutDir $SafeName

    try {
        wevtutil epl "$Channel" "$OutFile" /ow:true   # overwrite silently
        Write-Host "✓ Exported $Channel"
    }
    catch {
        Write-Warning "⚠️  Failed to export $Channel — $_"
    }
}

# ── Copy Intune Management Extension logs ─────────────────────────────────────
if (Test-Path $IMEsrcPath) {
    try {
        Copy-Item -Path (Join-Path $IMEsrcPath '*') `
                  -Destination $IMEdstPath `
                  -Recurse -Force
        Write-Host "✓ Copied IME logs to $IMEdstPath"
    }
    catch {
        Write-Warning "⚠️  Failed to copy IME logs — $_"
    }
}
else {
    Write-Warning "⚠️  IME log folder not found: $IMEsrcPath"
}

# ── Zip everything under C:\IntuneLogs ────────────────────────────────────────
try {
    Compress-Archive -Path "$OutDir\*" -DestinationPath $ZipPath -Force
    Write-Host "Logs zipped to $ZipPath"
}
catch {
    Write-Warning "⚠️  Compress-Archive failed — $_"
}
