<#
.SYNOPSIS
    Exports Autopilot hardware hash and writes it to USB or C:\HWID if no USB is found.
.DESCRIPTION
    Saves Get-WindowsAutoPilotInfo.ps1 to C:\PowerShell, extracts the HASH ID with Group Tag "migrate", and writes it as Autopilot_<Serial>.csv.
    Detects USB drives via physical media and logical mapping.
.AUTHOR
    H4L-MK4
.VERSION
    1.8
#>

param ()

function Get-UsbDrive {
    try {
        Write-Host "Detecting USB drives..."

        $usbDrives = @()

        $diskDrives = Get-CimInstance -ClassName Win32_DiskDrive | Where-Object { $_.InterfaceType -eq 'USB' }

        foreach ($disk in $diskDrives) {
            $partitions = Get-CimAssociatedInstance -InputObject $disk -ResultClassName Win32_DiskPartition

            foreach ($partition in $partitions) {
                $logicalDisks = Get-CimAssociatedInstance -InputObject $partition -ResultClassName Win32_LogicalDisk

                foreach ($ld in $logicalDisks) {
                    Write-Host "Found USB drive at $($ld.DeviceID)"
                    $usbDrives += $ld.DeviceID
                }
            }
        }

        return $usbDrives | Select-Object -First 1
    } catch {
        Write-Error "Error while detecting USB drives: $_"
        return $null
    }
}

function Get-SerialNumber {
    try {
        return (Get-CimInstance -ClassName Win32_BIOS).SerialNumber.Trim()
    } catch {
        Write-Error "Unable to get serial number: $_"
        exit 1
    }
}

function Ensure-AutopilotScript {
    try {
        Write-Host "Ensuring Get-WindowsAutoPilotInfo.ps1 is saved in C:\PowerShell..."

        $installPath = "C:\PowerShell"

        if (-not (Test-Path $installPath)) {
            New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        }

        $scriptPath = Join-Path -Path $installPath -ChildPath "Get-WindowsAutoPilotInfo.ps1"

        if (-not (Test-Path $scriptPath)) {
            Save-Script -Name Get-WindowsAutoPilotInfo -Path $installPath -Force
        }

        return $scriptPath
    } catch {
        Write-Error "Failed to install or prepare Get-WindowsAutoPilotInfo.ps1: $_"
        exit 1
    }
}

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

    $autopilotScript = Ensure-AutopilotScript
    $usb = Get-UsbDrive
    $serial = Get-SerialNumber
    $fileName = "Autopilot_$serial.csv"

    if ($usb) {
        $destination = Join-Path -Path $usb -ChildPath $fileName
        Write-Host "Saving to USB: $destination"
    } else {
        $fallbackPath = "C:\HWID"
        if (-not (Test-Path $fallbackPath)) {
            New-Item -Path $fallbackPath -ItemType Directory -Force | Out-Null
        }
        $destination = Join-Path -Path $fallbackPath -ChildPath $fileName
        Write-Host "No USB found. Saving to fallback: $destination"
    }

    & $autopilotScript -OutputFile $destination -GroupTag "migrate"

    Write-Host "SUCCESS: Autopilot hash saved to $destination"
} catch {
    Write-Error "Script failed: $_"
    exit 1
}
