<#
.SYNOPSIS
    Windows Package Manager maintenance script.

.DESCRIPTION
    Checks winget, finds available package updates, upgrades packages,
    retries failed upgrades, and saves a log file to C:\temp.

.NOTES
    Run PowerShell as Administrator.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ---------------- CONFIGURATION ----------------

$LogDirectory = "C:\temp"

if (-not (Test-Path -LiteralPath $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}

$LogFile = Join-Path $LogDirectory (
    "WingetMaintenance_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
)

$MaxRetryAttempts = 3
$RetryDelaySeconds = 10

$script:WingetPath = $null
$script:UpgradedCount = 0
$script:FailedCount = 0
$script:FailedPackages = [System.Collections.Generic.List[string]]::new()

# ---------------- FUNCTIONS ----------------

function Write-Log {
    param(
        [AllowEmptyString()]
        [string]$Message = "",

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[{0}] [{1}] {2}" -f $Timestamp, $Level, $Message

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
        Add-Content `
            -LiteralPath $LogFile `
            -Value $LogMessage `
            -Encoding UTF8
    }
    catch {
        Write-Host "Unable to write to log file: $LogFile" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}


function Show-Separator {
    Write-Log "================================================================"
}

function Find-WingetExecutable {
    Write-Log "Searching for winget.exe..."

    $PossiblePaths = [System.Collections.Generic.List[string]]::new()

    # First check the normal PATH.
    $PathWinget = Get-Command winget.exe -ErrorAction SilentlyContinue

    if ($null -ne $PathWinget -and $PathWinget.Source) {
        $PossiblePaths.Add($PathWinget.Source)
    }

    # Check the WindowsApps folder used by App Installer.
    $WindowsAppsPath = Join-Path $env:ProgramFiles "WindowsApps"

    if (Test-Path -LiteralPath $WindowsAppsPath) {
        try {
            $WindowsAppWingetFiles = Get-ChildItem `
                -LiteralPath $WindowsAppsPath `
                -Filter "winget.exe" `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue

            foreach ($File in $WindowsAppWingetFiles) {
                $PossiblePaths.Add($File.FullName)
            }
        }
        catch {
            Write-Log "Could not search WindowsApps recursively: $($_.Exception.Message)" "WARNING"
        }
    }

    # Check the Windows App Installer installation location.
    $AppInstallerLocations = @(
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
    )

    foreach ($Location in $AppInstallerLocations) {
        $Files = Get-ChildItem `
            -Path $Location `
            -Filter "winget.exe" `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue

        foreach ($File in $Files) {
            $PossiblePaths.Add($File.FullName)
        }
    }

    $WingetCandidates = @(
        $PossiblePaths |
            Where-Object {
                $_ -and (Test-Path -LiteralPath $_)
            } |
            Sort-Object -Unique
    )

    if ($WingetCandidates.Count -eq 0) {
        Write-Log "Could not find winget.exe." "ERROR"
        return $null
    }

    # Select the highest-version App Installer path when possible.
    $SelectedWinget = $WingetCandidates |
        Sort-Object {
            try {
                [version](
                    Split-Path $_ -Parent |
                    Split-Path -Leaf |
                    Select-String -Pattern "\d+\.\d+\.\d+\.\d+" |
                    ForEach-Object { $_.Matches.Value }
                )
            }
            catch {
                [version]"0.0.0.0"
            }
        } -Descending |
        Select-Object -First 1

    if (-not $SelectedWinget) {
        $SelectedWinget = $WingetCandidates | Select-Object -First 1
    }

    Write-Log "Using winget executable: $SelectedWinget" "SUCCESS"
    return $SelectedWinget
}

function Test-WingetAvailability {
    Write-Log "Checking winget availability..."

    try {
        $script:WingetPath = Find-WingetExecutable

        if ([string]::IsNullOrWhiteSpace($script:WingetPath)) {
            Write-Log "winget.exe could not be found." "ERROR"
            return $false
        }

        $VersionOutput = & $script:WingetPath --version 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Winget is available: $VersionOutput" "SUCCESS"
            return $true
        }

        Write-Log "Winget was found but could not be started." "ERROR"
        return $false
    }
    catch {
        Write-Log "Error checking winget: $($_.Exception.Message)" "ERROR"
        return $false
    }
}


function Update-Winget {
    Write-Log "Skipping self-update of winget/App Installer."
    Write-Log "The installed winget version is already available for this script." "INFO"
    return $true
}


function Get-AvailableUpgrades {
    Write-Log "Checking for available package upgrades..."

    try {
        $Output = & $script:WingetPath upgrade `
            --accept-source-agreements `
            --include-unknown 2>&1

        $ExitCode = $LASTEXITCODE
        $OutputText = $Output | Out-String

        Add-Content -LiteralPath $LogFile -Value ""
        Add-Content -LiteralPath $LogFile -Value "=== Available Upgrades ==="
        Add-Content -LiteralPath $LogFile -Value $OutputText -Encoding UTF8

        if ($ExitCode -ne 0) {
            Write-Log "Winget failed while checking for upgrades. Exit code: $ExitCode" "ERROR"
            Write-Log "Winget output: $OutputText" "ERROR"
            return $false
        }

        if (
            $OutputText -match "No applicable upgrade found" -or
            $OutputText -match "No available upgrade found" -or
            $OutputText -match "No installed package found"
        ) {
            Write-Log "All packages are up to date." "SUCCESS"
            return $true
        }

        Write-Log "Available upgrade information was written to the log." "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Error checking for upgrades: $($_.Exception.Message)" "ERROR"
        return $false
    }
}


function Get-UpgradePackageIds {
    try {
        $Output = & $script:WingetPath upgrade `
            --accept-source-agreements `
            --include-unknown 2>&1

        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        $PackageIds = foreach ($Line in @($Output)) {
            $Text = [string]$Line

            # Attempts to identify the package ID from winget table output.
            # Header and separator lines are ignored.
            if (
                $Text -notmatch "^-{3,}" -and
                $Text -notmatch "Name\s+Id\s+Version" -and
                $Text -notmatch "No applicable upgrade found" -and
                $Text -notmatch "No available upgrade found"
            ) {
                if ($Text -match "^\s*(?<Name>.+?)\s{2,}(?<Id>[A-Za-z0-9][A-Za-z0-9._\-]+)\s{2,}") {
                    $Matches["Id"]
                }
            }
        }

        return @($PackageIds | Sort-Object -Unique)
    }
    catch {
        Write-Log "Error reading package IDs: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

function Upgrade-Package {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [int]$Attempt = 1
    )

    Write-Log "Upgrading $PackageId (attempt $Attempt/$MaxRetryAttempts)..."

    try {
        $Output = & $script:WingetPath upgrade `
            --id $PackageId `
            --exact `
            --silent `
            --accept-source-agreements `
            --accept-package-agreements 2>&1

        $OutputText = $Output | Out-String

        Add-Content -LiteralPath $LogFile -Value ""
        Add-Content -LiteralPath $LogFile -Value "=== Upgrade: $PackageId ==="
        Add-Content -LiteralPath $LogFile -Value $OutputText -Encoding UTF8

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully upgraded: $PackageId" "SUCCESS"
            return $true
        }

        # Exit code 3010 indicates success, but a restart is required.
        if ($LASTEXITCODE -eq 3010) {
            Write-Log "Upgraded $PackageId; restart required." "WARNING"
            return $true
        }

        if ($Attempt -lt $MaxRetryAttempts) {
            Write-Log "Upgrade failed. Retrying in $RetryDelaySeconds seconds..." "WARNING"
            Start-Sleep -Seconds $RetryDelaySeconds

            return Upgrade-Package `
                -PackageId $PackageId `
                -Attempt ($Attempt + 1)
        }

        Write-Log "Failed to upgrade $PackageId after $MaxRetryAttempts attempts." "ERROR"
        return $false
    }
    catch {
        if ($Attempt -lt $MaxRetryAttempts) {
            Write-Log "Error upgrading $PackageId. Retrying in $RetryDelaySeconds seconds..." "WARNING"
            Start-Sleep -Seconds $RetryDelaySeconds

            return Upgrade-Package `
                -PackageId $PackageId `
                -Attempt ($Attempt + 1)
        }

        Write-Log "Exception upgrading $PackageId`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Upgrade-AllPackages {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$PackageIds
    )

    if ($PackageIds.Count -eq 0) {
        Write-Log "No packages require upgrading." "INFO"
        return
    }

    Write-Log "Starting package upgrade process..."
    Write-Log "Packages to process: $($PackageIds.Count)"

    Add-Content -LiteralPath $LogFile -Value ""
    Add-Content -LiteralPath $LogFile -Value "=== Upgrade Process ==="

    $PackageNumber = 0

    foreach ($PackageId in $PackageIds) {
        $PackageNumber++

        Write-Log ""
        Write-Log "[$PackageNumber/$($PackageIds.Count)] Processing: $PackageId"

        $Success = Upgrade-Package -PackageId $PackageId

        if ($Success) {
            $script:UpgradedCount++
        }
        else {
            $script:FailedCount++
            $script:FailedPackages.Add($PackageId)
        }

        if ($PackageNumber -lt $PackageIds.Count) {
            Start-Sleep -Seconds 2
        }
    }
}

function Show-UpgradeReport {
    param(
        [int]$TotalAttempted
    )

    Write-Log ""
    Show-Separator
    Write-Log "UPGRADE SUMMARY REPORT"
    Show-Separator

    Write-Log "Total Packages Attempted: $TotalAttempted"
    Write-Log "Successfully Upgraded: $script:UpgradedCount" "SUCCESS"

    if ($script:FailedCount -gt 0) {
        Write-Log "Failed Upgrades: $script:FailedCount" "ERROR"
        Write-Log ""
        Write-Log "Failed Packages:" "ERROR"

        foreach ($Package in $script:FailedPackages) {
            Write-Log " - $Package" "ERROR"
        }

        Write-Log ""
        Write-Log "Troubleshooting suggestions:" "WARNING"
        Write-Log "1. Run the upgrade manually."
        Write-Log "2. Check whether the package is pinned or blocked."
        Write-Log "3. Try: winget upgrade --id <package-id> --force"
        Write-Log "4. Restart Windows and run the script again."
    }
    else {
        Write-Log "Failed Upgrades: 0" "SUCCESS"
    }

if ($TotalAttempted -eq 0) {
    Write-Log "Result: No package updates were required." "SUCCESS"
    Write-Log "Success Rate: Not applicable - no updates were available." "SUCCESS"
}
else {
    $SuccessRate = [Math]::Round(
        ($script:UpgradedCount / $TotalAttempted) * 100,
        2
    )

    if ($script:FailedCount -eq 0) {
        Write-Log "Success Rate: $SuccessRate%" "SUCCESS"
    }
    else {
        Write-Log "Success Rate: $SuccessRate%" "WARNING"
    }
}


    Show-Separator
}

# ---------------- MAIN ----------------

function Main {
    try {
        Write-Log "WINDOWS PACKAGE MANAGER MAINTENANCE SCRIPT"
        Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Log "Log file: $LogFile"
        Show-Separator

        Write-Log "PHASE 1: WINGET AVAILABILITY CHECK"
        Show-Separator

        if (-not (Test-WingetAvailability)) {
            Write-Log "Winget is unavailable. The script cannot continue." "ERROR"
            return
        }

        Write-Log ""
        Write-Log "PHASE 2: CHECK WINGET"
        Show-Separator
		
		Write-Log "Using the installed winget executable: $script:WingetPath" "INFO"


        Write-Log ""
        Write-Log "PHASE 3: IDENTIFY AVAILABLE UPGRADES"
        Show-Separator

        $UpgradeCheckSucceeded = Get-AvailableUpgrades

        if (-not $UpgradeCheckSucceeded) {
            Write-Log "Could not determine available upgrades." "ERROR"
            return
        }

        Write-Log ""
        Write-Log "PHASE 4: PERFORM PACKAGE UPGRADES"
        Show-Separator

        $PackageIds = @(Get-UpgradePackageIds)

        if ($PackageIds.Count -gt 0) {
            Upgrade-AllPackages -PackageIds $PackageIds
        }
        else {
            Write-Log "No package upgrades were detected."
        }

        Show-UpgradeReport -TotalAttempted $PackageIds.Count

        Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Log "Log file saved to: $LogFile"
    }
    catch {
        Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

# ---------------- START SCRIPT ----------------

Main
