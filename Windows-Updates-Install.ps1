<#
.SYNOPSIS
    Windows Updates Installation Script
    Checks and installs all required PowerShell modules, then applies all available Windows updates

.DESCRIPTION
    This script performs comprehensive Windows update management including:
    - Verifies and installs required PowerShell modules (PSWindowsUpdate, NuGet)
    - Scans for all available Windows updates (Recommended and Optional)
    - Installs all available updates
    - Generates detailed update report
    - Handles update failures with logging
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Requires Windows 10/11
    Log file: $env:USERPROFILE\Documents\WindowsUpdates_YYYYMMDD_HHmmss.log
    Uses PSWindowsUpdate module for update management

.AUTHOR
    Windows Updates Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "WindowsUpdates_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$RequiredModules = @("PSWindowsUpdate", "NuGet")
$ModuleInstallAttempts = 3
$Script:InstalledUpdatesCount = 0
$Script:AvailableUpdatesCount = 0
$Script:FailedUpdatesCount = 0
$FailedUpdates = @()
$InstalledUpdates = @()

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

function Test-ModuleAvailability {
    <#
    .SYNOPSIS
        Check if a PowerShell module is installed
    #>
    param(
        [string]$ModuleName
    )
    
    try {
        $module = Get-Module -Name $ModuleName -ListAvailable
        if ($null -ne $module) {
            Write-Log "✓ Module found: $ModuleName (Version: $($module.Version))" "SUCCESS"
            return $true
        } else {
            Write-Log "✗ Module not found: $ModuleName" "WARNING"
            return $false
        }
    }
    catch {
        Write-Log "✗ Error checking module $ModuleName : $_" "WARNING"
        return $false
    }
}

function Install-Module {
    <#
    .SYNOPSIS
        Install a required PowerShell module
    #>
    param(
        [string]$ModuleName,
        [int]$Attempt = 1
    )
    
    Write-Log "Installing module: $ModuleName (Attempt $Attempt/$ModuleInstallAttempts)" "INFO"
    
    try {
        # Set PowerShell Gallery as trusted source
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        
        # Install the module
        Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
        
        Write-Log "✓ Successfully installed: $ModuleName" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "✗ Error installing $ModuleName : $_" "ERROR"
        
        if ($Attempt -lt $ModuleInstallAttempts) {
            Write-Log "Retrying in 10 seconds..." "WARNING"
            Start-Sleep -Seconds 10
            return Install-Module -ModuleName $ModuleName -Attempt ($Attempt + 1)
        } else {
            Write-Log "✗ Failed to install $ModuleName after $ModuleInstallAttempts attempts" "ERROR"
            return $false
        }
    }
}

function Verify-RequiredModules {
    <#
    .SYNOPSIS
        Verify and install all required PowerShell modules
    #>
    Write-Log "CHECKING REQUIRED POWERSHELL MODULES" "INFO"
    Show-Separator
    
    $allModulesAvailable = $true
    
    foreach ($module in $RequiredModules) {
        Write-Log "" "INFO"
        Write-Log "Module: $module" "INFO"
        
        if (-not (Test-ModuleAvailability -ModuleName $module)) {
            Write-Log "Attempting to install $module..." "WARNING"
            Write-Log "" "INFO"
            
            if (-not (Install-Module -ModuleName $module)) {
                Write-Log "Failed to install $module. This is required to continue." "ERROR"
                $allModulesAvailable = $false
            } else {
                Write-Log "Successfully installed $module" "SUCCESS"
            }
        }
        
        Write-Log "" "INFO"
    }
    
    if ($allModulesAvailable) {
        Write-Log "All required modules are available" "SUCCESS"
        return $true
    } else {
        Write-Log "Some required modules could not be installed" "ERROR"
        return $false
    }
}

function Import-RequiredModules {
    <#
    .SYNOPSIS
        Import all required modules into the current session
    #>
    Write-Log "Importing modules into current session..." "INFO"
    
    foreach ($module in $RequiredModules) {
        try {
            Import-Module -Name $module -Force -ErrorAction Stop
            Write-Log "✓ Imported: $module" "SUCCESS"
        }
        catch {
            Write-Log "✗ Error importing $module : $_" "ERROR"
            return $false
        }
    }
    
    return $true
}

function Get-AvailableUpdates {
    <#
    .SYNOPSIS
        Scan for all available Windows updates (Recommended and Optional)
    #>
    Write-Log "Scanning for available Windows updates..." "INFO"
    Write-Log "This may take several minutes..." "WARNING"
    
    try {
        # Get all available updates including optional ones
        $updates = Get-WindowsUpdate -AcceptAll
        
        if ($null -ne $updates) {
            Write-Log "✓ Found $($updates.Count) available update(s)" "INFO"
            
            Add-Content -Path $LogFile -Value ""
            Add-Content -Path $LogFile -Value "=== Available Updates ===" 
            
            $updateNumber = 0
            foreach ($update in $updates) {
                $updateNumber++
                $updateInfo = "[$updateNumber] KB$($update.KB) - $($update.Title) - $($update.Description)"
                Add-Content -Path $LogFile -Value $updateInfo
                Write-Log "  [$updateNumber] KB$($update.KB): $($update.Title)" "INFO"
            }
            
            Add-Content -Path $LogFile -Value ""
            $Script:AvailableUpdatesCount = $updates.Count
            return $updates
        } else {
            Write-Log "✓ No updates available. System is up to date." "SUCCESS"
            $Script:AvailableUpdatesCount = 0
            return $null
        }
    }
    catch {
        Write-Log "✗ Error scanning for updates: $_" "ERROR"
        return $null
    }
}

function Install-Updates {
    <#
    .SYNOPSIS
        Install all available Windows updates
    #>
    param(
        [object[]]$Updates
    )
    
    if ($null -eq $Updates -or $Updates.Count -eq 0) {
        Write-Log "No updates to install" "INFO"
        return
    }
    
    Write-Log "Starting Windows update installation process..." "INFO"
    Write-Log "Installing $($Updates.Count) update(s). This may take 30-60 minutes..." "WARNING"
    Add-Content -Path $LogFile -Value ""
    Add-Content -Path $LogFile -Value "=== Installation Process ===" 
    Add-Content -Path $LogFile -Value ""
    
    $updateNumber = 0
    foreach ($update in $Updates) {
        $updateNumber++
        Write-Log "" "INFO"
        Write-Log "[$updateNumber/$($Updates.Count)] Installing: KB$($update.KB) - $($update.Title)" "INFO"
        
        try {
            # Install individual update
            Install-WindowsUpdate -Update $update -AcceptAll -IgnoreReboot -ErrorAction Stop
            
            $Script:InstalledUpdatesCount++
            $InstalledUpdates += "KB$($update.KB) - $($update.Title)"
            Write-Log "[$updateNumber/$($Updates.Count)] ✓ Successfully installed" "SUCCESS"
            
            Add-Content -Path $LogFile -Value "Installed: KB$($update.KB) - $($update.Title) - SUCCESS"
        }
        catch {
            Write-Log "[$updateNumber/$($Updates.Count)] ✗ Failed to install: $_" "ERROR"
            
            $Script:FailedUpdatesCount++
            $FailedUpdates += "KB$($update.KB) - $($update.Title) - $_"
            
            Add-Content -Path $LogFile -Value "Failed: KB$($update.KB) - $($update.Title) - $_"
        }
    }
}

function Check-PendingRestarts {
    <#
    .SYNOPSIS
        Check if system restart is pending
    #>
    Write-Log "Checking for pending restart requirements..." "INFO"
    
    try {
        $pendingRestart = $false
        
        # Check various registry locations for restart requirements
        if (Test-Path "HKLM:\System\CurrentControlSet\Control\Session Manager") {
            $sessionManager = Get-Item "HKLM:\System\CurrentControlSet\Control\Session Manager"
            if ($sessionManager.GetValue("PendingFileRenameOperations") -or $sessionManager.GetValue("PendingFileRenameOperations2")) {
                $pendingRestart = $true
            }
        }
        
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update") {
            $winUpdate = Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
            if ($winUpdate.GetValue("RebootRequired") -eq 1) {
                $pendingRestart = $true
            }
        }
        
        if ($pendingRestart) {
            Write-Log "⚠ System restart is pending" "WARNING"
            Write-Log "A restart is required to complete the installation of updates" "WARNING"
            return $true
        } else {
            Write-Log "✓ No pending restart required at this time" "SUCCESS"
            return $false
        }
    }
    catch {
        Write-Log "Warning: Could not fully determine restart status: $_" "WARNING"
        return $false
    }
}

function Show-UpdateReport {
    <#
    .SYNOPSIS
        Display update installation summary report
    #>
    param(
        [int]$Available,
        [int]$Installed,
        [int]$Failed,
        [object[]]$InstalledList,
        [object[]]$FailedList,
        [bool]$RestartPending
    )
    
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "WINDOWS UPDATE INSTALLATION REPORT" "INFO"
    Show-Separator
    
    Write-Log "Total Updates Available: $Available" "INFO"
    Write-Log "Successfully Installed: $Installed" "SUCCESS"
    Write-Log "Failed Installations: $Failed" $(if ($Failed -gt 0) { "ERROR" } else { "SUCCESS" })
    
    if ($Installed -gt 0) {
        Write-Log "" "INFO"
        Write-Log "Installed Updates:" "SUCCESS"
        foreach ($update in $InstalledList) {
            Add-Content -Path $LogFile -Value "  ✓ $update"
            Write-Log "  ✓ $update" "SUCCESS"
        }
    }
    
    if ($Failed -gt 0) {
        Write-Log "" "INFO"
        Write-Log "Failed Updates:" "ERROR"
        foreach ($update in $FailedList) {
            Add-Content -Path $LogFile -Value "  ✗ $update"
            Write-Log "  ✗ $update" "ERROR"
        }
        Write-Log "" "INFO"
        Write-Log "Troubleshooting Tips:" "WARNING"
        Write-Log "  1. Check Windows Update logs in Event Viewer" "INFO"
        Write-Log "  2. Run: Get-WindowsUpdate -Verbose for detailed information" "INFO"
        Write-Log "  3. Some updates may require manual installation" "INFO"
    }
    
    Write-Log "" "INFO"
    if ($Available -gt 0) {
        $successRate = [math]::Round(($Installed / $Available) * 100, 2)
        Write-Log "Installation Success Rate: $successRate%" $(if ($successRate -eq 100) { "SUCCESS" } else { "WARNING" })
    }
    
    Write-Log "" "INFO"
    if ($RestartPending) {
        Write-Log "System Restart Status: RESTART PENDING" "WARNING"
        Write-Log "Please restart your computer to complete all updates" "WARNING"
    } else {
        Write-Log "System Restart Status: No restart pending" "SUCCESS"
    }
    
    Show-Separator
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "WINDOWS UPDATES INSTALLATION SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: VERIFY AND INSTALL REQUIRED MODULES =====
    Write-Log "PHASE 1: VERIFY POWERSHELL MODULES" "INFO"
    Show-Separator
    
    if (-not (Verify-RequiredModules)) {
        Write-Log "" "INFO"
        Write-Log "Cannot proceed without required modules." "ERROR"
        Write-Log "Please run this script again or manually install PSWindowsUpdate module." "ERROR"
        Write-Log "" "INFO"
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 2: IMPORT MODULES =====
    Write-Log "PHASE 2: IMPORT POWERSHELL MODULES" "INFO"
    Show-Separator
    
    if (-not (Import-RequiredModules)) {
        Write-Log "" "INFO"
        Write-Log "Failed to import required modules." "ERROR"
        Write-Log "" "INFO"
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 3: SCAN FOR UPDATES =====
    Write-Log "PHASE 3: SCAN FOR WINDOWS UPDATES" "INFO"
    Show-Separator
    
    $availableUpdates = Get-AvailableUpdates
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 4: INSTALL UPDATES =====
    Write-Log "PHASE 4: INSTALL WINDOWS UPDATES" "INFO"
    Show-Separator
    
    if ($null -ne $availableUpdates) {
        Install-Updates -Updates $availableUpdates
    }
    
    Write-Log "" "INFO"
    
    # ===== PHASE 5: CHECK FOR RESTART =====
    Write-Log "PHASE 5: CHECK RESTART STATUS" "INFO"
    Show-Separator
    
    $restartPending = Check-PendingRestarts
    
    Write-Log "" "INFO"
    
    # ===== COMPLETION SUMMARY =====
    Show-UpdateReport `
        -Available $Script:AvailableUpdatesCount `
        -Installed $Script:InstalledUpdatesCount `
        -Failed $Script:FailedUpdatesCount `
        -InstalledList $InstalledUpdates `
        -FailedList $FailedUpdates `
        -RestartPending $restartPending
    
    Write-Log "" "INFO"
    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log file saved to: $LogFile" "INFO"
    Write-Log "================================================================" "INFO"
    
    if ($restartPending) {
        Write-Log "" "INFO"
        Write-Log "⚠ IMPORTANT: Your system requires a restart to complete updates" "WARNING"
        Write-Log "" "INFO"
        $restartChoice = Read-Host "Would you like to restart now? (y/n)"
        if ($restartChoice -eq "y" -or $restartChoice -eq "Y") {
            Write-Log "Initiating system restart..." "WARNING"
            Add-Content -Path $LogFile -Value "System restart initiated by user"
            Start-Sleep -Seconds 3
            Restart-Computer -Force
        } else {
            Write-Log "Restart postponed by user" "INFO"
            Add-Content -Path $LogFile -Value "Restart postponed by user"
        }
    }
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Run main function
Main
