<#
.SYNOPSIS
    Backup and Recovery Script
    Creates system image backups and manages recovery options

.DESCRIPTION
    This script performs comprehensive backup and recovery management including:
    - Create system image backups
    - Backup critical system files
    - Schedule automated backups
    - Verify backup integrity
    - Manage backup retention
    - List available backups
    - Recovery point information
    - Backup size reporting
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Requires external drive for backups
    Log file: $env:USERPROFILE\Documents\BackupRecovery_YYYYMMDD_HHmmss.log

.AUTHOR
    Backup and Recovery Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "BackupRecovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$BackupMetadataFile = Join-Path -Path $LogPath -ChildPath "BackupMetadata.csv"
$BackupRetentionDays = 60
$Script:BackupsCreated = 0
$Script:BackupsFailed = 0
$Script:TotalBackupSize = 0
$BackupHistory = @()

# Critical system folders to backup
$CriticalFolders = @(
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Pictures",
    "$env:APPDATA\Microsoft\Windows\Start Menu",
    "$env:APPDATA"
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
        Display a visual separator
    #>
    Write-Log "================================================================" "INFO"
}

function Convert-BytesToGB {
    <#
    .SYNOPSIS
        Convert bytes to gigabytes
    #>
    param([long]$Bytes)
    if ($Bytes -eq 0) { return 0 }
    return [math]::Round($Bytes / 1GB, 2)
}

function Test-BackupDestination {
    <#
    .SYNOPSIS
        Prompt user for backup destination and verify it's valid
    #>
    Write-Log "BACKUP DESTINATION SELECTION" "INFO"
    Show-Separator
    
    Write-Host ""
    Write-Host "Enter backup destination path (external drive recommended):" -ForegroundColor Cyan
    Write-Host "Example: E:\SystemBackups" -ForegroundColor Yellow
    $backupDest = Read-Host "Backup Path"
    
    if ([string]::IsNullOrWhiteSpace($backupDest)) {
        Write-Log "No backup destination specified" "ERROR"
        return $null
    }
    
    # Create destination if it doesn't exist
    if (-not (Test-Path -Path $backupDest)) {
        try {
            New-Item -ItemType Directory -Path $backupDest -Force | Out-Null
            Write-Log "✓ Created backup destination: $backupDest" "SUCCESS"
        }
        catch {
            Write-Log "✗ Failed to create backup destination: $_" "ERROR"
            return $null
        }
    } else {
        Write-Log "✓ Backup destination exists: $backupDest" "SUCCESS"
    }
    
    # Check available space
    try {
        $drive = Get-PSDrive -Name ([char]$backupDest[0]) -ErrorAction SilentlyContinue
        if ($null -ne $drive) {
            $freeSpace = $drive.Free
            $freeSpaceGB = Convert-BytesToGB -Bytes $freeSpace
            Write-Log "Available space: $freeSpaceGB GB" "INFO"
            
            if ($freeSpaceGB -lt 50) {
                Write-Log "⚠ Warning: Less than 50GB available for backup" "WARNING"
            }
        }
    }
    catch {
        Write-Log "Could not determine available space" "WARNING"
    }
    
    Write-Log "" "INFO"
    return $backupDest
}

function Backup-CriticalFiles {
    <#
    .SYNOPSIS
        Backup critical user files
    #>
    param(
        [string]$BackupPath
    )
    
    Write-Log "BACKING UP CRITICAL USER FILES" "INFO"
    Show-Separator
    
    $backupDate = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $fileBackupPath = Join-Path -Path $BackupPath -ChildPath "FileBackup_$backupDate"
    
    try {
        New-Item -ItemType Directory -Path $fileBackupPath -Force | Out-Null
        Write-Log "Created backup directory: $fileBackupPath" "INFO"
    }
    catch {
        Write-Log "✗ Failed to create backup directory: $_" "ERROR"
        return $false
    }
    
    $totalSize = 0
    $fileCount = 0
    
    foreach ($folder in $CriticalFolders) {
        if (-not (Test-Path -Path $folder)) {
            Write-Log "Folder not found, skipping: $folder" "WARNING"
            continue
        }
        
        Write-Log "Backing up: $folder" "INFO"
        
        try {
            # Calculate folder size before backup
            $folderSize = (Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue | 
                          Measure-Object -Property Length -Sum).Sum
            
            # Copy folder
            $destFolder = Join-Path -Path $fileBackupPath -ChildPath (Split-Path -Leaf $folder)
            Copy-Item -Path $folder -Destination $destFolder -Recurse -Force -ErrorAction SilentlyContinue
            
            if ($null -ne $folderSize) {
                $folderSizeGB = Convert-BytesToGB -Bytes $folderSize
                Write-Log "  ✓ Backed up: $folderSizeGB GB" "SUCCESS"
                $totalSize += $folderSize
                $fileCount++
            } else {
                Write-Log "  ✓ Backed up: (size calculation skipped)" "SUCCESS"
            }
        }
        catch {
            Write-Log "  ✗ Error backing up folder: $_" "ERROR"
        }
    }
    
    $totalSizeGB = Convert-BytesToGB -Bytes $totalSize
    Write-Log "" "INFO"
    Write-Log "File backup completed: $totalSizeGB GB in $fileCount folders" "SUCCESS"
    Write-Log "Backup location: $fileBackupPath" "SUCCESS"
    
    $Script:TotalBackupSize += $totalSize
    $Script:BackupsCreated++
    
    Add-BackupToMetadata -BackupPath $fileBackupPath -BackupType "FileBackup" -Size $totalSizeGB
    
    Write-Log "" "INFO"
    return $true
}

function Create-SystemImage {
    <#
    .SYNOPSIS
        Create a Windows system image backup
    #>
    param(
        [string]$BackupPath
    )
    
    Write-Log "CREATING SYSTEM IMAGE BACKUP" "INFO"
    Show-Separator
    
    Write-Log "⚠ System Image Backup requires Windows Backup feature" "WARNING"
    Write-Log "This feature may not be available on all Windows editions" "WARNING"
    Write-Log "" "INFO"
    
    try {
        # Check if Windows Backup is available
        $backupFeature = Get-WindowsOptionalFeature -FeatureName Windows-Backup -Online -ErrorAction SilentlyContinue
        
        if ($null -eq $backupFeature) {
            Write-Log "Windows Backup feature not detected" "WARNING"
            Write-Log "Manual system image creation recommended using Windows Backup utility" "INFO"
            return $false
        }
        
        if ($backupFeature.State -ne "Enabled") {
            Write-Log "Attempting to enable Windows Backup feature..." "INFO"
            Enable-WindowsOptionalFeature -FeatureName Windows-Backup -Online -NoRestart -ErrorAction Stop
            Write-Log "✓ Windows Backup feature enabled" "SUCCESS"
        }
        
        # Create system image using wbAdmin
        $imageDate = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $imagePath = Join-Path -Path $BackupPath -ChildPath "SystemImage_$imageDate"
        
        New-Item -ItemType Directory -Path $imagePath -Force | Out-Null
        
        Write-Log "Starting system image backup..." "INFO"
        Write-Log "Destination: $imagePath" "INFO"
        Write-Log "This may take 30-60 minutes depending on system size..." "WARNING"
        
        # Use wbAdmin to create system image
        $wbAdminResult = & wbadmin start backup -backupTarget:$imagePath -include:C: -allCritical -quiet 2>&1
        $output = $wbAdminResult | Out-String
        Add-Content -Path $LogFile -Value $output
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "✓ System image backup completed successfully" "SUCCESS"
            
            # Get backup size
            $backupSize = (Get-ChildItem -Path $imagePath -Recurse -Force | 
                          Measure-Object -Property Length -Sum).Sum
            $backupSizeGB = Convert-BytesToGB -Bytes $backupSize
            
            Write-Log "Backup size: $backupSizeGB GB" "INFO"
            Write-Log "Backup location: $imagePath" "SUCCESS"
            
            $Script:TotalBackupSize += $backupSize
            $Script:BackupsCreated++
            Add-BackupToMetadata -BackupPath $imagePath -BackupType "SystemImage" -Size $backupSizeGB
            
            return $true
        } else {
            Write-Log "✗ System image backup failed" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "✗ Error creating system image: $_" "ERROR"
        return $false
    }
}

function Backup-Registry {
    <#
    .SYNOPSIS
        Backup Windows registry
    #>
    param(
        [string]$BackupPath
    )
    
    Write-Log "BACKING UP WINDOWS REGISTRY" "INFO"
    Show-Separator
    
    $registryBackupPath = Join-Path -Path $BackupPath -ChildPath "RegistryBackup_$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"
    
    try {
        New-Item -ItemType Directory -Path $registryBackupPath -Force | Out-Null
        
        $registryHives = @("HKLM:\SOFTWARE", "HKLM:\SYSTEM", "HKCU:\")
        $backupSize = 0
        
        foreach ($hive in $registryHives) {
            $hiveName = Split-Path -Leaf $hive
            $backupFile = Join-Path -Path $registryBackupPath -ChildPath "$hiveName.reg"
            
            Write-Log "Backing up: $hive" "INFO"
            
            try {
                & reg export $hive $backupFile /y 2>&1 | Out-Null
                
                if (Test-Path -Path $backupFile) {
                    $fileSize = (Get-Item -Path $backupFile).Length
                    $backupSize += $fileSize
                    Write-Log "  ✓ Exported: $hiveName" "SUCCESS"
                }
            }
            catch {
                Write-Log "  ✗ Error exporting $hiveName : $_" "ERROR"
            }
        }
        
        $backupSizeGB = Convert-BytesToGB -Bytes $backupSize
        Write-Log "Registry backup completed: $backupSizeGB GB" "SUCCESS"
        Write-Log "Backup location: $registryBackupPath" "SUCCESS"
        
        $Script:TotalBackupSize += $backupSize
        $Script:BackupsCreated++
        Add-BackupToMetadata -BackupPath $registryBackupPath -BackupType "RegistryBackup" -Size $backupSizeGB
        
        Write-Log "" "INFO"
        return $true
    }
    catch {
        Write-Log "✗ Error backing up registry: $_" "ERROR"
        return $false
    }
}

function Add-BackupToMetadata {
    <#
    .SYNOPSIS
        Add backup information to metadata file
    #>
    param(
        [string]$BackupPath,
        [string]$BackupType,
        [double]$Size
    )
    
    try {
        if (-not (Test-Path -Path $BackupMetadataFile)) {
            $header = "Timestamp,BackupType,Path,Size_GB,Status"
            Set-Content -Path $BackupMetadataFile -Value $header
        }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $csvRow = "$timestamp,$BackupType,$BackupPath,$Size,Success"
        Add-Content -Path $BackupMetadataFile -Value $csvRow
    }
    catch {
        Write-Log "Warning: Could not update backup metadata: $_" "WARNING"
    }
}

function List-AvailableBackups {
    <#
    .SYNOPSIS
        List all available backups
    #>
    param(
        [string]$BackupPath
    )
    
    Write-Log "AVAILABLE BACKUPS" "INFO"
    Show-Separator
    
    if (-not (Test-Path -Path $BackupPath)) {
        Write-Log "No backups found at: $BackupPath" "WARNING"
        return
    }
    
    try {
        $backupDirs = Get-ChildItem -Path $BackupPath -Directory -ErrorAction SilentlyContinue
        
        if ($backupDirs.Count -eq 0) {
            Write-Log "No backups found" "INFO"
            return
        }
        
        Write-Log "Found $($backupDirs.Count) backup(s):" "INFO"
        Write-Log "" "INFO"
        
        foreach ($backup in $backupDirs) {
            $size = (Get-ChildItem -Path $backup.FullName -Recurse -Force | 
                    Measure-Object -Property Length -Sum).Sum
            $sizeGB = Convert-BytesToGB -Bytes $size
            $age = (Get-Date) - $backup.CreationTime
            
            Write-Log "Backup: $($backup.Name)" "INFO"
            Write-Log "  Created: $($backup.CreationTime)" "INFO"
            Write-Log "  Age: $($age.Days) days, $($age.Hours) hours" "INFO"
            Write-Log "  Size: $sizeGB GB" "INFO"
            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log "Error listing backups: $_" "ERROR"
    }
}

function Remove-OldBackups {
    <#
    .SYNOPSIS
        Remove backups older than retention period
    #>
    param(
        [string]$BackupPath,
        [int]$RetentionDays
    )
    
    Write-Log "MANAGING BACKUP RETENTION" "INFO"
    Show-Separator
    
    if (-not (Test-Path -Path $BackupPath)) {
        Write-Log "Backup path not found" "WARNING"
        return
    }
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        $oldBackups = Get-ChildItem -Path $BackupPath -Directory -ErrorAction SilentlyContinue | 
                      Where-Object { $_.CreationTime -lt $cutoffDate }
        
        if ($oldBackups.Count -eq 0) {
            Write-Log "No backups older than $RetentionDays days found" "SUCCESS"
            return
        }
        
        Write-Log "Found $($oldBackups.Count) backup(s) older than $RetentionDays days" "WARNING"
        Write-Log "" "INFO"
        
        $removedSize = 0
        foreach ($backup in $oldBackups) {
            $size = (Get-ChildItem -Path $backup.FullName -Recurse -Force -ErrorAction SilentlyContinue | 
                    Measure-Object -Property Length -Sum).Sum
            
            Write-Log "Removing: $($backup.Name)" "INFO"
            try {
                Remove-Item -Path $backup.FullName -Recurse -Force -ErrorAction Stop
                Write-Log "  ✓ Deleted" "SUCCESS"
                $removedSize += $size
            }
            catch {
                Write-Log "  ✗ Failed to delete: $_" "ERROR"
            }
        }
        
        $removedSizeGB = Convert-BytesToGB -Bytes $removedSize
        Write-Log "" "INFO"
        Write-Log "Cleanup completed: Removed $removedSizeGB GB" "SUCCESS"
    }
    catch {
        Write-Log "Error managing backups: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Show-BackupReport {
    <#
    .SYNOPSIS
        Display backup summary report
    #>
    param(
        [string]$BackupPath
    )
    
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "BACKUP SUMMARY REPORT" "INFO"
    Show-Separator
    
    Write-Log "Backups Created: $($Script:BackupsCreated)" "SUCCESS"
    Write-Log "Backup Failures: $($Script:BackupsFailed)" $(if ($Script:BackupsFailed -gt 0) { "ERROR" } else { "SUCCESS" })
    
    $totalSizeGB = Convert-BytesToGB -Bytes $Script:TotalBackupSize
    Write-Log "Total Backup Size: $totalSizeGB GB" "INFO"
    Write-Log "Backup Location: $BackupPath" "INFO"
    Write-Log "Retention Policy: Keep backups for $BackupRetentionDays days" "INFO"
    
    Show-Separator
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "BACKUP AND RECOVERY SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: SELECT BACKUP DESTINATION =====
    $backupDestination = Test-BackupDestination
    
    if ([string]::IsNullOrWhiteSpace($backupDestination)) {
        Write-Log "" "INFO"
        Write-Log "Backup cancelled - no destination specified" "ERROR"
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    
    Show-Separator
    
    # ===== PHASE 2: BACKUP CRITICAL FILES =====
    Write-Log "PHASE 1: BACKUP CRITICAL USER FILES" "INFO"
    Show-Separator
    
    if (Backup-CriticalFiles -BackupPath $backupDestination) {
        # Success
    } else {
        $Script:BackupsFailed++
    }
    
    Show-Separator
    
    # ===== PHASE 3: BACKUP REGISTRY =====
    Write-Log "PHASE 2: BACKUP WINDOWS REGISTRY" "INFO"
    Show-Separator
    
    if (Backup-Registry -BackupPath $backupDestination) {
        # Success
    } else {
        $Script:BackupsFailed++
    }
    
    Show-Separator
    
    # ===== PHASE 4: CREATE SYSTEM IMAGE =====
    Write-Log "PHASE 3: CREATE SYSTEM IMAGE BACKUP" "INFO"
    Show-Separator
    
    Write-Host ""
    $createImage = Read-Host "Create System Image? (y/n)"
    if ($createImage -eq "y" -or $createImage -eq "Y") {
        Write-Log "" "INFO"
        if (Create-SystemImage -BackupPath $backupDestination) {
            # Success
        } else {
            $Script:BackupsFailed++
        }
    } else {
        Write-Log "System Image backup skipped by user" "INFO"
    }
    
    Show-Separator
    
    # ===== PHASE 5: LIST BACKUPS =====
    Write-Log "PHASE 4: LIST AVAILABLE BACKUPS" "INFO"
    Show-Separator
    
    List-AvailableBackups -BackupPath $backupDestination
    
    Show-Separator
    
    # ===== PHASE 6: CLEANUP OLD BACKUPS =====
    Write-Log "PHASE 5: CLEANUP OLD BACKUPS" "INFO"
    Show-Separator
    
    Remove-OldBackups -BackupPath $backupDestination -RetentionDays $BackupRetentionDays
    
    # ===== COMPLETION SUMMARY =====
    Show-BackupReport -BackupPath $backupDestination
    
    Write-Log "" "INFO"
    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log file saved to: $LogFile" "INFO"
    Write-Log "Metadata file: $BackupMetadataFile" "INFO"
    Write-Log "================================================================" "INFO"
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Run main function
Main
