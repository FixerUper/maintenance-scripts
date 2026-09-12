<#
.SYNOPSIS
    Scans for and installs available Windows updates.

.DESCRIPTION
    Requires Administrator privileges and Windows 10/11.
    Uses the PSWindowsUpdate module.
    Logs results to the user's Documents folder.

.NOTES
    Run this script as Administrator.
#>

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -----------------------------
# Configuration
# -----------------------------

$DocumentsPath = "C:\Temp"

New-Item `
    -Path $DocumentsPath `
    -ItemType Directory `
    -Force `
    -ErrorAction Stop | Out-Null

$LogFile = Join-Path `
    $DocumentsPath `
    ("WindowsUpdates_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

New-Item `
    -Path $LogFile `
    -ItemType File `
    -Force `
    -ErrorAction Stop | Out-Null

$ModuleName = "PSWindowsUpdate"

$script:AvailableUpdatesCount = 0
$script:InstalledUpdatesCount = 0
$script:FailedUpdatesCount = 0

$script:InstalledUpdates = [System.Collections.Generic.List[string]]::new()
$script:FailedUpdates = [System.Collections.Generic.List[string]]::new()

# -----------------------------
# Logging
# -----------------------------

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[{0}] [{1}] {2}" -f `
        $Timestamp, $Level, $Message

    switch ($Level) {
        "INFO" {
            Write-Host $LogMessage -ForegroundColor White
        }
        "WARNING" {
            Write-Host $LogMessage -ForegroundColor Yellow
        }
        "ERROR" {
            Write-Host $LogMessage -ForegroundColor Red
        }
        "SUCCESS" {
            Write-Host $LogMessage -ForegroundColor Green
        }
    }

    try {
        $ParentFolder = Split-Path -Path $LogFile -Parent

        if (-not (Test-Path -LiteralPath $ParentFolder)) {
            New-Item `
                -Path $ParentFolder `
                -ItemType Directory `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        if (-not (Test-Path -LiteralPath $LogFile)) {
            New-Item `
                -Path $LogFile `
                -ItemType File `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        Add-Content `
            -LiteralPath $LogFile `
            -Value $LogMessage `
            -ErrorAction Stop
    }
    catch {
        # Do not stop the update process merely because logging failed.
        Write-Host "Logging failed: $($_.Exception.Message)" `
            -ForegroundColor DarkYellow
    }
}

function Show-Separator {
    Write-Log ("=" * 70)
}

# -----------------------------
# Module management
# -----------------------------

function Test-RequiredModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        $Module = Get-Module -Name $Name -ListAvailable |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($null -ne $Module) {
            Write-Log "Module found: $Name, version $($Module.Version)" "SUCCESS"
            return $true
        }

        Write-Log "Module not found: $Name" "WARNING"
        return $false
    }
    catch {
        Write-Log "Error checking module $Name`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-RequiredModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        Write-Log "Preparing PowerShell Gallery..."

        $Repository = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue

        if ($null -ne $Repository -and
            $Repository.InstallationPolicy -ne "Trusted") {
            Set-PSRepository -Name "PSGallery" `
                -InstallationPolicy Trusted
        }

        if (-not (Get-PackageProvider -Name NuGet `
                -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Log "Installing NuGet package provider..."
            Install-PackageProvider -Name NuGet `
                -MinimumVersion "2.8.5.201" `
                -Force
        }

        Write-Log "Installing module: $Name"

        # The & operator is important because this function is not named
        # Install-Module and therefore does not shadow the PowerShell cmdlet.
        & Microsoft.PowerShell.PSResourceGet\Install-PSResource `
            -Name $Name `
            -Scope CurrentUser `
            -TrustRepository `
            -Reinstall:$false `
            -ErrorAction Stop

        Write-Log "Successfully installed module: $Name" "SUCCESS"
        return $true
    }
    catch {
        # Fall back to the traditional PowerShellGet cmdlet if available.
        try {
            Microsoft.PowerShell.Core\Install-Module `
                -Name $Name `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -ErrorAction Stop

            Write-Log "Successfully installed module: $Name" "SUCCESS"
            return $true
        }
        catch {
            Write-Log "Failed to install $Name`: $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
}

function Ensure-RequiredModule {
    if (-not (Test-RequiredModule -Name $ModuleName)) {
        if (-not (Install-RequiredModule -Name $ModuleName)) {
            throw "Required module '$ModuleName' could not be installed."
        }
    }

    try {
        Import-Module -Name $ModuleName -Force -ErrorAction Stop
        Write-Log "Imported module: $ModuleName" "SUCCESS"
    }
    catch {
        throw "Could not import $ModuleName`: $($_.Exception.Message)"
    }
}

# -----------------------------
# Windows Update operations
# -----------------------------

function Get-AvailableWindowsUpdates {
    [CmdletBinding()]
    param ()

    try {
        Write-Log "Scanning for available Windows updates..."
        Write-Log "This may take several minutes." "WARNING"

        $Updates = @(Get-WindowsUpdate -AcceptAll -IgnoreReboot)

        $script:AvailableUpdatesCount = $Updates.Count

        if ($Updates.Count -eq 0) {
            Write-Log "No updates are available." "SUCCESS"
            return @()
        }

        Write-Log "Found $($Updates.Count) update(s)." "SUCCESS"

        Add-Content -LiteralPath $LogFile -Value ""
        Add-Content -LiteralPath $LogFile -Value "=== Available Updates ==="

        foreach ($Update in $Updates) {
            $KB = if ($Update.KB) {
                "KB$($Update.KB)"
            }
            else {
                "No KB number"
            }

            $Line = "$KB - $($Update.Title)"

            Write-Log $Line
            Add-Content -LiteralPath $LogFile -Value $Line
        }

        return $Updates
    }
    catch {
        Write-Log "Error scanning for updates`: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

function Install-WindowsUpdates {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Updates
    )

    if ($Updates.Count -eq 0) {
        Write-Log "There are no updates to install."
        return
    }

    Write-Log "Starting installation of $($Updates.Count) update(s)." "WARNING"

    try {
        # Install the updates returned by the Windows Update scan.
        # The pipeline avoids the unsupported -Update parameter.
        $InstallResults = @(
            Get-WindowsUpdate `
                -AcceptAll `
                -IgnoreReboot `
                -ErrorAction Stop |
            Install-WindowsUpdate `
                -AcceptAll `
                -IgnoreReboot `
                -ErrorAction Stop
        )

        foreach ($Result in $InstallResults) {
            $KB = if ($Result.KB) {
                "KB$($Result.KB)"
            }
            elseif ($Result.KBArticleID) {
                $Result.KBArticleID
            }
            else {
                "No KB number"
            }

            $Title = if ($Result.Title) {
                $Result.Title
            }
            else {
                "Update"
            }

            $Status = if ($Result.Result) {
                $Result.Result
            }
            else {
                "Processed"
            }

            if ($Status -match "Failed|Error") {
                $script:FailedUpdatesCount++
                $script:FailedUpdates.Add("$KB - $Title - $Status")

                Write-Log "$KB failed: $Status" "ERROR"
            }
            else {
                $script:InstalledUpdatesCount++
                $script:InstalledUpdates.Add("$KB - $Title")

                Write-Log "$KB installed: $Status" "SUCCESS"
            }
        }

        # Some versions return little or no pipeline output even after
        # successfully completing the installation.
        if ($InstallResults.Count -eq 0) {
            Write-Log "The update installation command completed." "SUCCESS"
        }
    }
    catch {
        $script:FailedUpdatesCount++

        $ErrorText = $_.Exception.Message
        $script:FailedUpdates.Add("Windows Update installation - $ErrorText")

        Write-Log "Windows Update installation failed: $ErrorText" "ERROR"
    }
}

# -----------------------------
# Restart detection
# -----------------------------

function Test-PendingRestart {
    [CmdletBinding()]
    param ()

    $RestartPending = $false

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )

    foreach ($Path in $RegistryPaths) {
        if (Test-Path $Path) {
            $RestartPending = $true
        }
    }

    $SessionManagerPath =
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"

    if (Test-Path $SessionManagerPath) {
        $SessionManager = Get-ItemProperty `
            -Path $SessionManagerPath `
            -ErrorAction SilentlyContinue

        if ($null -ne $SessionManager.PendingFileRenameOperations) {
            $RestartPending = $true
        }
    }

    return $RestartPending
}

# -----------------------------
# Report
# -----------------------------

function Show-UpdateReport {
    param (
        [bool]$RestartPending
    )

    Show-Separator
    Write-Log "WINDOWS UPDATE INSTALLATION REPORT"
    Show-Separator

    Write-Log "Updates available: $script:AvailableUpdatesCount"
    Write-Log "Successfully installed: $script:InstalledUpdatesCount" "SUCCESS"

    if ($script:FailedUpdatesCount -gt 0) {
        Write-Log "Failed installations: $script:FailedUpdatesCount" "ERROR"
    }
    else {
        Write-Log "Failed installations: 0" "SUCCESS"
    }

    if ($script:InstalledUpdates.Count -gt 0) {
        Write-Log "Installed updates:" "SUCCESS"

        foreach ($Update in $script:InstalledUpdates) {
            Write-Log "  $Update" "SUCCESS"
        }
    }

    if ($script:FailedUpdates.Count -gt 0) {
        Write-Log "Failed updates:" "ERROR"

        foreach ($Update in $script:FailedUpdates) {
            Write-Log "  $Update" "ERROR"
        }
    }

    if ($RestartPending) {
        Write-Log "A restart is required to complete the updates." "WARNING"
    }
    else {
        Write-Log "No restart is currently required." "SUCCESS"
    }

    Show-Separator
}

# -----------------------------
# Main execution
# -----------------------------

try {
    Show-Separator
    Write-Log "WINDOWS UPDATES INSTALLATION SCRIPT"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Log file: $LogFile"
    Show-Separator

    Ensure-RequiredModule

    $AvailableUpdates = @(Get-AvailableWindowsUpdates)

    if ($AvailableUpdates.Count -gt 0) {
        Install-WindowsUpdates -Updates $AvailableUpdates
    }
	else {
    Write-Log "No updates were found."
	}

    $RestartPending = Test-PendingRestart

    Show-UpdateReport -RestartPending $RestartPending

    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "SUCCESS"
    Write-Log "Log saved to: $LogFile"

    if ($RestartPending) {
        $RestartChoice = Read-Host "Restart the computer now? (y/n)"

        if ($RestartChoice -match "^[Yy]$") {
            Write-Log "Restarting computer..." "WARNING"
            Restart-Computer -Force
        }
        else {
            Write-Log "Restart postponed by user."
        }
    }
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
    exit 1
}
