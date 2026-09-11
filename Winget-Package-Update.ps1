<#
.SYNOPSIS
    Windows Package Manager (winget) Maintenance Script
    Upgrades all installed packages and manages software updates

.DESCRIPTION
    This script performs comprehensive package management including:
    - Checks winget availability and updates the package manager
    - Lists all installed packages
    - Upgrades all available packages
    - Handles upgrade failures with retry logic
    - Generates detailed upgrade report
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Requires Windows 10/11 with winget installed
    Log file: $env:USERPROFILE\Documents\WingetMaintenance_YYYYMMDD_HHmmss.log

.AUTHOR
    Winget Maintenance Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "WingetMaintenance_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$MaxRetryAttempts = 3
$RetryDelaySeconds = 10
$Script:UpgradedCount = 0
$Script:FailedCount = 0
$Script:SkippedCount = 0
$FailedPackages = @()

# ========== FUNCTIONS ==========

function Write-Log {
    <#
    .SYNOPSIS
        Write messages to both console and log file
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color coding
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor White }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logMessage
}

function Show-Separator {
    <#
    .SYNOPSIS
        Display a visual separator in logs
    #>
    Write-Log "================================================================" "INFO"
}

function Test-WingetAvailability {
    <#
    .SYNOPSIS
        Check if winget is installed and accessible
    #>
    Write-Log "Checking winget availability..." "INFO"
    
    try {
        $wingetVersion = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "✓ Winget is available: $wingetVersion" "SUCCESS"
            return $true
        } else {
            Write-Log "✗ Winget not found or not accessible" "ERROR"
            Write-Log "Please ensure Windows Package Manager is installed from Microsoft Store" "WARNING"
            return $false
        }
    }
    catch {
        Write-Log "✗ Error checking winget: $_" "ERROR"
        return $false
    }
}

function Update-Winget {
    <#
    .SYNOPSIS
        Update winget itself
    #>
    Write-Log "Updating Windows Package Manager (winget)..." "INFO"
    
    try {
        $result = & winget upgrade Microsoft.DesktopAppInstaller 2>&1
        $output = $result | Out-String
        Add-Content -Path $LogFile -Value $output
        
        if ($LASTEXITCODE -eq 0 -or $output -match "No installed packages found matching") {
            Write-Log "✓ Winget is up to date" "SUCCESS"
            return $true
        } else {
            Write-Log "Winget update completed" "INFO"
            return $true
        }
    }
    catch {
        Write-Log "✗ Error updating winget: $_" "WARNING"
        return $false
    }
}

function Get-InstalledPackages {
    <#
    .SYNOPSIS
        Retrieve list of all installed packages
    #>
    Write-Log "Retrieving list of installed packages..." "INFO"
    
    try {
        $packages = & winget list --output json 2>&1 | ConvertFrom-Json
        
        if ($null -ne $packages -and $packages.Count -gt 0) {
            Write-Log "✓ Found $($packages.Count) installed packages" "SUCCESS"
            return $packages
        } else {
            Write-Log "✗ No packages found or unable to parse package list" "WARNING"
            return $null
        }
    }
    catch {
        Write-Log "✗ Error retrieving package list: $_" "ERROR"
        return $null
    }
}

function Get-AvailableUpgrades {
    <#
    .SYNOPSIS
        Get list of packages with available upgrades
    #>
    Write-Log "Checking for available package upgrades..." "INFO"
    
    try {
        $upgrades = & winget upgrade --output json 2>&1 | ConvertFrom-Json
        
        if ($null -ne $upgrades -and $upgrades.Count -gt 0) {
            Write-Log "✓ Found $($upgrades.Count) packages with available upgrades" "INFO"
            Add-Content -Path $LogFile -Value ""
            Add-Content -Path $LogFile -Value "=== Available Upgrades ===" 
            
            foreach ($package in $upgrades) {
                $pkgInfo = "Package: $($package.Name) | Current: $($package.Version) | Latest: $($package.AvailableVersion)"
                Add-Content -Path $LogFile -Value $pkgInfo
                Write-Log "  • $($package.Name): $($package.Version) → $($package.AvailableVersion)" "INFO"
            }
            
            Add-Content -Path $LogFile -Value ""
            return $upgrades
        } else {
            Write-Log "✓ All packages are up to date" "SUCCESS"
            return $null
        }
    }
    catch {
        Write-Log "✗ Error checking for upgrades: $_" "ERROR"
        return $null
    }
}

function Upgrade-Package {
    <#
    .SYNOPSIS
        Upgrade a single package with retry logic
    #>
    param(
        [string]$PackageId,
        [string]$PackageName,
        [int]$Attempt = 1
    )
    
    Write-Log "Upgrading: $PackageName (Attempt $Attempt/$MaxRetryAttempts)" "INFO"
    
    try {
        $result = & winget upgrade --id $PackageId --accept-source-agreements --accept-package-agreements 2>&1
        $output = $result | Out-String
        Add-Content -Path $LogFile -Value $output
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "✓ Successfully upgraded: $PackageName" "SUCCESS"
            return "success"
        } elseif ($LASTEXITCODE -eq 3010) {
            Write-Log "⚠ Upgraded $PackageName (restart required)" "WARNING"
            return "success_restart_needed"
        } else {
            if ($Attempt -lt $MaxRetryAttempts) {
                Write-Log "⚠ Upgrade failed, retrying in $RetryDelaySeconds seconds..." "WARNING"
                Start-Sleep -Seconds $RetryDelaySeconds
                return Upgrade-Package -PackageId $PackageId -PackageName $PackageName -Attempt ($Attempt + 1)
            } else {
                Write-Log "✗ Failed to upgrade: $PackageName after $MaxRetryAttempts attempts" "ERROR"
                return "failed"
            }
        }
    }
    catch {
        if ($Attempt -lt $MaxRetryAttempts) {
            Write-Log "⚠ Error during upgrade, retrying in $RetryDelaySeconds seconds..." "WARNING"
            Start-Sleep -Seconds $RetryDelaySeconds
            return Upgrade-Package -PackageId $PackageId -PackageName $PackageName -Attempt ($Attempt + 1)
        } else {
            Write-Log "✗ Exception upgrading $PackageName : $_" "ERROR"
            return "failed"
        }
    }
}

function Upgrade-AllPackages {
    <#
    .SYNOPSIS
        Upgrade all available packages
    #>
    param(
        [object[]]$Packages
    )
    
    if ($null -eq $Packages -or $Packages.Count -eq 0) {
        Write-Log "No packages to upgrade" "INFO"
        return
    }
    
    Write-Log "Starting package upgrade process..." "INFO"
    Write-Log "Total packages to upgrade: $($Packages.Count)" "INFO"
    Add-Content -Path $LogFile -Value ""
    Add-Content -Path $LogFile -Value "=== Upgrade Process ===" 
    Add-Content -Path $LogFile -Value ""
    
    $packageNumber = 0
    foreach ($package in $Packages) {
        $packageNumber++
        Write-Log "" "INFO"
        Write-Log "[$packageNumber/$($Packages.Count)] Processing: $($package.Name)" "INFO"
        
        $upgradeResult = Upgrade-Package -PackageId $package.Id -PackageName $package.Name
        
        switch ($upgradeResult) {
            "success" {
                $Script:UpgradedCount++
                Write-Log "[$packageNumber/$($Packages.Count)] ✓ Completed" "SUCCESS"
            }
            "success_restart_needed" {
                $Script:UpgradedCount++
                Write-Log "[$packageNumber/$($Packages.Count)] ✓ Completed (Restart needed)" "SUCCESS"
            }
            "failed" {
                $Script:FailedCount++
                $FailedPackages += $package.Name
                Write-Log "[$packageNumber/$($Packages.Count)] ✗ Failed" "ERROR"
            }
        }
        
        # Small delay between package upgrades to avoid overwhelming system
        if ($packageNumber -lt $Packages.Count) {
            Start-Sleep -Seconds 2
        }
    }
}

function Show-UpgradeReport {
    <#
    .SYNOPSIS
        Display upgrade summary report
    #>
    param(
        [int]$TotalAttempted,
        [int]$Successful,
        [int]$Failed,
        [string[]]$FailedList
    )
    
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "UPGRADE SUMMARY REPORT" "INFO"
    Show-Separator
    
    Write-Log "Total Packages Attempted: $TotalAttempted" "INFO"
    Write-Log "Successfully Upgraded: $Successful" "SUCCESS"
    Write-Log "Failed Upgrades: $Failed" $(if ($Failed -gt 0) { "ERROR" } else { "SUCCESS" })
    
    if ($Failed -gt 0) {
        Write-Log "" "INFO"
        Write-Log "Failed Packages:" "ERROR"
        foreach ($failedPkg in $FailedList) {
            Write-Log "  • $failedPkg" "ERROR"
        }
        Write-Log "" "INFO"
        Write-Log "Troubleshooting Tips:" "WARNING"
        Write-Log "  1. Some packages may require manual intervention" "INFO"
        Write-Log "  2. Check if the package is pinned or locked" "INFO"
        Write-Log "  3. Try running: winget upgrade --id <package-id> --force" "INFO"
        Write-Log "  4. Restart Windows and try again" "INFO"
    }
    
    Write-Log "" "INFO"
    Write-Log "Success Rate: $([math]::Round(($Successful / [math]::Max($TotalAttempted, 1)) * 100, 2))%" $(if ($Failed -eq 0) { "SUCCESS" } else { "WARNING" })
    
    Show-Separator
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "WINDOWS PACKAGE MANAGER (WINGET) MAINTENANCE SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: WINGET AVAILABILITY CHECK =====
    Write-Log "PHASE 1: WINGET AVAILABILITY CHECK" "INFO"
    Show-Separator
    
    if (-not (Test-WingetAvailability)) {
        Write-Log "" "INFO"
        Write-Log "Winget is not available. Cannot continue." "ERROR"
        Write-Log "To install winget, visit: https://github.com/microsoft/winget-cli/releases" "INFO"
        Write-Log "" "INFO"
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 2: UPDATE WINGET =====
    Write-Log "PHASE 2: UPDATE PACKAGE MANAGER" "INFO"
    Show-Separator
    
    Update-Winget
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 3: CHECK FOR UPGRADES =====
    Write-Log "PHASE 3: IDENTIFY AVAILABLE UPGRADES" "INFO"
    Show-Separator
    
    $availableUpgrades = Get-AvailableUpgrades
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 4: PERFORM UPGRADES =====
    Write-Log "PHASE 4: PERFORM PACKAGE UPGRADES" "INFO"
    Show-Separator
    
    if ($null -ne $availableUpgrades) {
        Upgrade-AllPackages -Packages $availableUpgrades
        $totalAttempted = $availableUpgrades.Count
    } else {
        $totalAttempted = 0
        Write-Log "No packages to upgrade" "INFO"
    }
    
    Write-Log "" "INFO"
    
    # ===== COMPLETION SUMMARY =====
    Show-UpgradeReport -TotalAttempted $totalAttempted -Successful $Script:UpgradedCount -Failed $Script:FailedCount -FailedList $FailedPackages
    
    Write-Log "" "INFO"
    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log file saved to: $LogFile" "INFO"
    Write-Log "================================================================" "INFO"
    
    if ($Script:FailedCount -gt 0) {
        Write-Log "" "INFO"
        Write-Log "Note: Some packages failed to upgrade. Review the log for details." "WARNING"
    }
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Run main function
Main
