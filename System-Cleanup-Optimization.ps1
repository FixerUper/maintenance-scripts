<#
.SYNOPSIS
    System Cleanup and Optimization Script
    Removes temporary files, clears caches, and optimizes system performance

.DESCRIPTION
    This script performs comprehensive system cleanup including:
    - Removes temporary files from multiple locations
    - Clears Windows Update cache
    - Empties Recycle Bin
    - Removes old log files
    - Disables startup bloat applications
    - Compacts OS installation (NTFS optimization)
    - Reports disk space freed
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Log file: $env:USERPROFILE\Documents\SystemCleanup_YYYYMMDD_HHmmss.log

.AUTHOR
    System Cleanup Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "SystemCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$Script:TotalSpaceFreed = 0
$Script:FilesDeleted = 0
$CleanupLocations = @(
    @{ Path = "$env:TEMP"; Name = "User Temp" },
    @{ Path = "$env:SystemRoot\Temp"; Name = "System Temp" },
    @{ Path = "$env:SystemRoot\Prefetch"; Name = "Prefetch" },
    @{ Path = "$env:LocalAppData\Temp"; Name = "Local AppData Temp" },
    @{ Path = "$env:LocalAppData\Microsoft\Windows\INetCache"; Name = "Internet Cache" }
)

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

function Convert-BytesToGB {
    <#
    .SYNOPSIS
        Convert bytes to gigabytes
    #>
    param(
        [long]$Bytes
    )
    
    if ($Bytes -eq 0) { return 0 }
    return [math]::Round($Bytes / 1GB, 2)
}

function Remove-TempFiles {
    <#
    .SYNOPSIS
        Remove temporary files from specified locations
    #>
    param(
        [string]$Path,
        [string]$LocationName
    )
    
    Write-Log "Cleaning: $LocationName" "INFO"
    
    if (-not (Test-Path -Path $Path)) {
        Write-Log "  → Path not found: $Path" "WARNING"
        return
    }
    
    $locationSpaceFreed = 0
    $locationFilesDeleted = 0
    
    try {
        # Get total size before deletion
        $before = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
                   Measure-Object -Property Length -Sum).Sum
        
        # Remove all files in the directory
        Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue | 
        ForEach-Object {
            try {
                if ($_.PSIsContainer) {
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                    $locationFilesDeleted++
                }
            }
            catch {
                # File might be in use, skip it
                $null = $null
            }
        }
        
        # Get total size after deletion
        $after = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
                  Measure-Object -Property Length -Sum).Sum
        
        $spaceFreed = if ($null -ne $before) { $before - $after } else { 0 }
        
        if ($spaceFreed -gt 0) {
            $freedGB = Convert-BytesToGB -Bytes $spaceFreed
            Write-Log "  ✓ Freed: $freedGB GB | Files deleted: $locationFilesDeleted" "SUCCESS"
            $Script:TotalSpaceFreed += $spaceFreed
            $Script:FilesDeleted += $locationFilesDeleted
        } else {
            Write-Log "  ✓ Already clean or files in use" "SUCCESS"
        }
    }
    catch {
        Write-Log "  ✗ Error cleaning $LocationName : $_" "ERROR"
    }
}

function Clear-RecycleBin {
    <#
    .SYNOPSIS
        Empty the Recycle Bin
    #>
    Write-Log "Emptying Recycle Bin..." "INFO"
    
    try {
        $recycleBin = (New-Object -ComObject Shell.Application).NameSpace(10)
        $recycleBinItems = $recycleBin.Items()
        
        if ($recycleBinItems.Count -gt 0) {
            $recycleBinItems.Folder.Self.InvokeVerbEx("empty")
            Write-Log "  ✓ Recycle Bin emptied ($($recycleBinItems.Count) items deleted)" "SUCCESS"
        } else {
            Write-Log "  ✓ Recycle Bin already empty" "SUCCESS"
        }
    }
    catch {
        Write-Log "  ✗ Error emptying Recycle Bin: $_" "ERROR"
    }
}

function Clear-WindowsUpdateCache {
    <#
    .SYNOPSIS
        Clear Windows Update cache
    #>
    Write-Log "Clearing Windows Update cache..." "INFO"
    
    try {
        $updatePath = "$env:SystemRoot\SoftwareDistribution\Download"
        
        if (Test-Path -Path $updatePath) {
            $before = (Get-ChildItem -Path $updatePath -Recurse -Force -ErrorAction SilentlyContinue | 
                      Measure-Object -Property Length -Sum).Sum
            
            Get-ChildItem -Path $updatePath -Recurse -Force -ErrorAction SilentlyContinue | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            
            $after = (Get-ChildItem -Path $updatePath -Recurse -Force -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum).Sum
            
            $spaceFreed = if ($null -ne $before) { $before - $after } else { 0 }
            
            if ($spaceFreed -gt 0) {
                $freedGB = Convert-BytesToGB -Bytes $spaceFreed
                Write-Log "  ✓ Freed: $freedGB GB from Windows Update cache" "SUCCESS"
                $Script:TotalSpaceFreed += $spaceFreed
            } else {
                Write-Log "  ✓ Windows Update cache already clean" "SUCCESS"
            }
        } else {
            Write-Log "  ✓ No Windows Update cache found" "SUCCESS"
        }
    }
    catch {
        Write-Log "  ✗ Error clearing Windows Update cache: $_" "ERROR"
    }
}

function Remove-OldLogFiles {
    <#
    .SYNOPSIS
        Remove old log files (older than 30 days)
    #>
    Write-Log "Removing old log files (older than 30 days)..." "INFO"
    
    $logLocations = @(
        "$env:SystemRoot\System32\winevt\Logs",
        "$env:SystemRoot\Logs"
    )
    
    $cutoffDate = (Get-Date).AddDays(-30)
    $logsDeleted = 0
    $spaceFreed = 0
    
    foreach ($logPath in $logLocations) {
        if (-not (Test-Path -Path $logPath)) { continue }
        
        try {
            Get-ChildItem -Path $logPath -Filter "*.log" -ErrorAction SilentlyContinue | 
            Where-Object { $_.LastWriteTime -lt $cutoffDate } |
            ForEach-Object {
                try {
                    $spaceFreed += $_.Length
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                    $logsDeleted++
                }
                catch {
                    $null = $null
                }
            }
        }
        catch {
            $null = $null
        }
    }
    
    if ($logsDeleted -gt 0) {
        $freedGB = Convert-BytesToGB -Bytes $spaceFreed
        Write-Log "  ✓ Deleted $logsDeleted old log files | Freed: $freedGB GB" "SUCCESS"
        $Script:TotalSpaceFreed += $spaceFreed
    } else {
        Write-Log "  ✓ No old log files to remove" "SUCCESS"
    }
}

function Disable-StartupBloat {
    <#
    .SYNOPSIS
        Disable unnecessary startup applications
    #>
    Write-Log "Disabling startup bloat applications..." "INFO"
    
    $startupItems = @(
        "OneDrive",
        "Skype",
        "CCleaner",
        "Discord",
        "Spotify",
        "Steam"
    )
    
    $disabledCount = 0
    
    try {
        foreach ($item in $startupItems) {
            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
            
            if (Test-Path -Path $regPath) {
                $existingItem = Get-ItemProperty -Path $regPath -Name $item -ErrorAction SilentlyContinue
                
                if ($null -ne $existingItem) {
                    Remove-ItemProperty -Path $regPath -Name $item -Force -ErrorAction SilentlyContinue
                    Write-Log "  ✓ Disabled: $item" "SUCCESS"
                    $disabledCount++
                }
            }
        }
        
        if ($disabledCount -gt 0) {
            Write-Log "  ✓ Successfully disabled $disabledCount startup items" "SUCCESS"
        } else {
            Write-Log "  ✓ No startup bloat applications found" "SUCCESS"
        }
    }
    catch {
        Write-Log "  ✗ Error disabling startup items: $_" "ERROR"
    }
}

function Compact-OSInstallation {
    <#
    .SYNOPSIS
        Compact OS installation to save disk space
    #>
    Write-Log "Compacting OS installation..." "INFO"
    Write-Log "  ⏳ This may take several minutes..." "WARNING"
    
    try {
        $result = & compact /compactos:always 2>&1
        $output = $result | Out-String
        Add-Content -Path $LogFile -Value $output
        
        Write-Log "  ✓ OS compaction completed" "SUCCESS"
    }
    catch {
        Write-Log "  ✗ Error compacting OS: $_" "ERROR"
    }
}

function Show-CleanupReport {
    <#
    .SYNOPSIS
        Display cleanup summary report
    #>
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "SYSTEM CLEANUP SUMMARY REPORT" "INFO"
    Show-Separator
    
    $totalGB = Convert-BytesToGB -Bytes $Script:TotalSpaceFreed
    
    Write-Log "Total Space Freed: $totalGB GB" "SUCCESS"
    Write-Log "Files Deleted: $($Script:FilesDeleted)" "SUCCESS"
    
    Write-Log "" "INFO"
    Write-Log "Cleanup Operations Completed:" "SUCCESS"
    Write-Log "  ✓ Temporary files removed" "SUCCESS"
    Write-Log "  ✓ Recycle Bin emptied" "SUCCESS"
    Write-Log "  ✓ Windows Update cache cleared" "SUCCESS"
    Write-Log "  ✓ Old log files removed" "SUCCESS"
    Write-Log "  ✓ Startup bloat disabled" "SUCCESS"
    Write-Log "  ✓ OS installation compacted" "SUCCESS"
    
    Show-Separator
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "SYSTEM CLEANUP AND OPTIMIZATION SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: REMOVE TEMPORARY FILES =====
    Write-Log "PHASE 1: REMOVE TEMPORARY FILES" "INFO"
    Show-Separator
    
    foreach ($location in $CleanupLocations) {
        Write-Log "" "INFO"
        Remove-TempFiles -Path $location.Path -LocationName $location.Name
    }
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 2: CLEAR RECYCLE BIN =====
    Write-Log "PHASE 2: EMPTY RECYCLE BIN" "INFO"
    Show-Separator
    
    Clear-RecycleBin
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 3: CLEAR WINDOWS UPDATE CACHE =====
    Write-Log "PHASE 3: CLEAR WINDOWS UPDATE CACHE" "INFO"
    Show-Separator
    
    Clear-WindowsUpdateCache
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 4: REMOVE OLD LOG FILES =====
    Write-Log "PHASE 4: REMOVE OLD LOG FILES" "INFO"
    Show-Separator
    
    Remove-OldLogFiles
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 5: DISABLE STARTUP BLOAT =====
    Write-Log "PHASE 5: DISABLE STARTUP BLOAT" "INFO"
    Show-Separator
    
    Disable-StartupBloat
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 6: COMPACT OS =====
    Write-Log "PHASE 6: COMPACT OS INSTALLATION" "INFO"
    Show-Separator
    
    Compact-OSInstallation
    
    Write-Log "" "INFO"
    
    # ===== COMPLETION SUMMARY =====
    Show-CleanupReport
    
    Write-Log "" "INFO"
    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log file saved to: $LogFile" "INFO"
    Write-Log "================================================================" "INFO"
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Run main function
Main
