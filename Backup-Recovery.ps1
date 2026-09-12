<#
.SYNOPSIS
Backup and Recovery Script

.DESCRIPTION
Backs up selected user folders, exports important registry hives,
optionally creates a Windows system image, lists backups, and removes
backups older than the retention period.

.NOTES
Requires Administrator privileges.
Log file and metadata are stored in C:\temp.
System-image backups require a separate destination volume.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION
# ============================================================================

$LogPath = 'C:\temp'
$LogFileName = "BackupRecovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$BackupMetadataFile = Join-Path -Path $LogPath -ChildPath 'BackupMetadata.csv'
$BackupRetentionDays = 60

$Script:BackupsCreated = 0
$Script:BackupsFailed = 0
$Script:TotalBackupSize = [int64]0

$CriticalFolders = @(
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path $env:USERPROFILE 'Downloads'),
    (Join-Path $env:USERPROFILE 'Pictures'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu')
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Initialize-Logging {
    if (-not (Test-Path -LiteralPath $LogPath)) {
        New-Item `
            -ItemType Directory `
            -Path $LogPath `
            -Force |
            Out-Null
    }

    if (-not (Test-Path -LiteralPath $LogFile)) {
        New-Item `
            -ItemType File `
            -Path $LogFile `
            -Force |
            Out-Null
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'INFO' {
            Write-Host $logMessage -ForegroundColor White
        }
        'WARNING' {
            Write-Host $logMessage -ForegroundColor Yellow
        }
        'ERROR' {
            Write-Host $logMessage -ForegroundColor Red
        }
        'SUCCESS' {
            Write-Host $logMessage -ForegroundColor Green
        }
    }

    Add-Content `
        -LiteralPath $LogFile `
        -Value $logMessage `
        -Encoding UTF8
}

function Show-Separator {
    Write-Log ('=' * 72) 'INFO'
}

function Convert-BytesToGB {
    param(
        [AllowNull()]
        [long]$Bytes
    )

    if ($null -eq $Bytes -or $Bytes -le 0) {
        return [double]0
    }

    return [math]::Round($Bytes / 1GB, 2)
}

function Get-FolderSize {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int64]0
    }

    $result = Get-ChildItem `
        -LiteralPath $Path `
        -Recurse `
        -Force `
        -File `
        -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum

    if ($null -eq $result.Sum) {
        return [int64]0
    }

    return [int64]$result.Sum
}

function Add-BackupToMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,

        [Parameter(Mandatory = $true)]
        [string]$BackupType,

        [Parameter(Mandatory = $true)]
        [double]$SizeGB,

        [string]$Status = 'Success'
    )

    try {
        $record = [PSCustomObject]@{
            Timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            BackupType = $BackupType
            Path       = $BackupPath
            Size_GB    = $SizeGB
            Status     = $Status
        }

        if (Test-Path -LiteralPath $BackupMetadataFile) {
            $record |
                Export-Csv `
                    -LiteralPath $BackupMetadataFile `
                    -NoTypeInformation `
                    -Append `
                    -Encoding UTF8
        }
        else {
            $record |
                Export-Csv `
                    -LiteralPath $BackupMetadataFile `
                    -NoTypeInformation `
                    -Encoding UTF8
        }
    }
    catch {
        Write-Log `
            "Could not update metadata file: $($_.Exception.Message)" `
            'WARNING'
    }
}

# ============================================================================
# BACKUP DESTINATION
# ============================================================================

function Test-BackupDestination {
    Write-Log 'BACKUP DESTINATION SELECTION' 'INFO'
    Show-Separator

    Write-Host ''
    Write-Host 'Enter the backup destination path.' -ForegroundColor Cyan
    Write-Host 'An external drive is recommended.' -ForegroundColor Yellow
    Write-Host 'Example: E:\SystemBackups' -ForegroundColor Yellow

    $backupDest = Read-Host 'Backup Path'

    if ([string]::IsNullOrWhiteSpace($backupDest)) {
        Write-Log 'No backup destination was specified.' 'ERROR'
        return $null
    }

    $backupDest = $backupDest.Trim()

    try {
        if (-not (Test-Path -LiteralPath $backupDest)) {
            New-Item `
                -ItemType Directory `
                -Path $backupDest `
                -Force |
                Out-Null

            Write-Log `
                "Created backup destination: $backupDest" `
                'SUCCESS'
        }
        else {
            Write-Log `
                "Backup destination exists: $backupDest" `
                'SUCCESS'
        }

        $resolvedPath = (Resolve-Path -LiteralPath $backupDest).Path
        $freeSpaceGB = [double]::PositiveInfinity

        $root = [System.IO.Path]::GetPathRoot($resolvedPath)

        if ($root -and $root -match '^[A-Za-z]:\\$') {
            $driveName = $root.Substring(0, 1)
            $drive = Get-PSDrive `
                -Name $driveName `
                -ErrorAction SilentlyContinue

            if ($null -ne $drive) {
                $freeSpaceGB = Convert-BytesToGB -Bytes $drive.Free
                Write-Log `
                    "Available space: $freeSpaceGB GB" `
                    'INFO'
            }
        }

        if ($freeSpaceGB -lt 50) {
            Write-Log `
                'Less than 50 GB is available on the destination drive.' `
                'WARNING'
        }

        return $resolvedPath
    }
    catch {
        Write-Log `
            "Unable to use backup destination: $($_.Exception.Message)" `
            'ERROR'

        return $null
    }
}

# ============================================================================
# USER FILE BACKUP
# ============================================================================

function Backup-CriticalFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    Write-Log 'BACKING UP CRITICAL USER FILES' 'INFO'
    Show-Separator

    $backupDate = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $fileBackupPath = Join-Path `
        -Path $BackupPath `
        -ChildPath "FileBackup_$backupDate"

    $totalSize = [int64]0
    $folderCount = 0
    $hadErrors = $false

    try {
        New-Item `
            -ItemType Directory `
            -Path $fileBackupPath `
            -Force |
            Out-Null

        Write-Log `
            "Created backup directory: $fileBackupPath" `
            'INFO'
    }
    catch {
        Write-Log `
            "Failed to create backup directory: $($_.Exception.Message)" `
            'ERROR'

        return $false
    }

    foreach ($folder in $CriticalFolders) {
        if ([string]::IsNullOrWhiteSpace($folder)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            Write-Log `
                "Folder not found, skipping: $folder" `
                'WARNING'

            continue
        }

        try {
            $sourceItem = Get-Item -LiteralPath $folder
            $folderName = $sourceItem.Name

            if ([string]::IsNullOrWhiteSpace($folderName)) {
                $folderName = 'RootFolder'
            }

            $destinationFolder = Join-Path `
                -Path $fileBackupPath `
                -ChildPath $folderName

            Write-Log `
                "Backing up: $folder" `
                'INFO'

            $folderSize = Get-FolderSize -Path $folder

            New-Item `
                -ItemType Directory `
                -Path $destinationFolder `
                -Force |
                Out-Null

            # Copy the contents of the source folder.
            Get-ChildItem `
                -LiteralPath $folder `
                -Force |
                Copy-Item `
                    -Destination $destinationFolder `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop

            $totalSize += $folderSize
            $folderCount++

            Write-Log `
                "Backed up ${folderName}: $(Convert-BytesToGB -Bytes $folderSize) GB" `
                'SUCCESS'
        }
        catch {
            $hadErrors = $true

            Write-Log `
                "Error backing up ${folder}: $($_.Exception.Message)" `
                'ERROR'
        }
    }

    $totalSizeGB = Convert-BytesToGB -Bytes $totalSize

    Write-Log `
        "File backup completed: $totalSizeGB GB in $folderCount folders" `
        'INFO'

    Write-Log `
        "Backup location: $fileBackupPath" `
        'SUCCESS'

    if ($folderCount -gt 0) {
        $Script:TotalBackupSize += $totalSize
        $Script:BackupsCreated++

        $backupStatus = if ($hadErrors) {
            'CompletedWithErrors'
        }
        else {
            'Success'
        }

        Add-BackupToMetadata `
            -BackupPath $fileBackupPath `
            -BackupType 'FileBackup' `
            -SizeGB $totalSizeGB `
            -Status $backupStatus
    }

    return (-not $hadErrors)
}

# ============================================================================
# REGISTRY BACKUP
# ============================================================================

function Backup-Registry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    Write-Log 'BACKING UP WINDOWS REGISTRY' 'INFO'
    Show-Separator

    $registryBackupPath = Join-Path `
        -Path $BackupPath `
        -ChildPath "RegistryBackup_$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"

    try {
        New-Item `
            -ItemType Directory `
            -Path $registryBackupPath `
            -Force |
            Out-Null
    }
    catch {
        Write-Log `
            "Failed to create registry backup directory: $($_.Exception.Message)" `
            'ERROR'

        return $false
    }

    # reg.exe expects registry root syntax, not PowerShell provider syntax.
    $registryHives = [ordered]@{
        'HKLM_SOFTWARE' = 'HKLM\SOFTWARE'
        'HKLM_SYSTEM'   = 'HKLM\SYSTEM'
        'HKCU'          = 'HKCU'
    }

    $backupSize = [int64]0
    $exportedCount = 0
    $hadErrors = $false

    foreach ($entry in $registryHives.GetEnumerator()) {
        $backupFile = Join-Path `
            -Path $registryBackupPath `
            -ChildPath "$($entry.Key).reg"

        Write-Log `
            "Exporting $($entry.Value)" `
            'INFO'

        try {
            $regOutput = & reg.exe export `
                $entry.Value `
                $backupFile `
                /y `
                2>&1

            $exitCode = $LASTEXITCODE

            if ($regOutput) {
                Add-Content `
                    -LiteralPath $LogFile `
                    -Value ($regOutput | Out-String) `
                    -Encoding UTF8
            }

            if (
                $exitCode -eq 0 -and
                (Test-Path -LiteralPath $backupFile)
            ) {
                $fileSize = (Get-Item -LiteralPath $backupFile).Length
                $backupSize += $fileSize
                $exportedCount++

                Write-Log `
                    "Exported $($entry.Value)" `
                    'SUCCESS'
            }
            else {
                $hadErrors = $true

                Write-Log `
                    "Failed to export $($entry.Value)" `
                    'ERROR'
            }
        }
        catch {
            $hadErrors = $true

            Write-Log `
                "Error exporting $($entry.Value): $($_.Exception.Message)" `
                'ERROR'
        }
    }

    $backupSizeGB = Convert-BytesToGB -Bytes $backupSize

    Write-Log `
        "Registry backup size: $backupSizeGB GB" `
        'INFO'

    Write-Log `
        "Registry backup location: $registryBackupPath" `
        'SUCCESS'

    if ($exportedCount -gt 0) {
        $Script:TotalBackupSize += $backupSize
        $Script:BackupsCreated++

        $backupStatus = if ($hadErrors) {
            'CompletedWithErrors'
        }
        else {
            'Success'
        }

        Add-BackupToMetadata `
            -BackupPath $registryBackupPath `
            -BackupType 'RegistryBackup' `
            -SizeGB $backupSizeGB `
            -Status $backupStatus
    }

    return ($exportedCount -gt 0 -and -not $hadErrors)
}

# ============================================================================
# SYSTEM IMAGE BACKUP
# ============================================================================

function Create-SystemImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    Write-Log 'CREATING SYSTEM IMAGE BACKUP' 'INFO'
    Show-Separator

    if (-not (Get-Command wbadmin.exe -ErrorAction SilentlyContinue)) {
        Write-Log `
            'wbadmin.exe was not found on this system.' `
            'ERROR'

        return $false
    }

    try {
        $resolvedBackupPath = (Resolve-Path -LiteralPath $BackupPath).Path
        $backupRoot = [System.IO.Path]::GetPathRoot($resolvedBackupPath)

        if ($backupRoot -notmatch '^[A-Za-z]:\\$') {
            Write-Log `
                'System-image backup requires a local drive-letter destination.' `
                'ERROR'

            return $false
        }

        $backupDrive = $backupRoot.Substring(0, 1).ToUpperInvariant()
        $systemDrive = $env:SystemDrive.Substring(0, 1).ToUpperInvariant()

        if ($backupDrive -eq $systemDrive) {
            Write-Log `
                'Do not store the system image on the Windows system drive.' `
                'ERROR'

            return $false
        }

        Write-Log `
            "System-image target volume: ${backupDrive}:" `
            'INFO'

        Write-Log `
            'wbadmin will manage the WindowsImageBackup folder on that volume.' `
            'WARNING'

        Write-Log `
            'This operation may take a considerable amount of time.' `
            'WARNING'

        $arguments = @(
            'start',
            'backup',
            "-backupTarget:${backupDrive}:",
            '-include:C:',
            '-allCritical',
            '-quiet'
        )

        $output = & wbadmin.exe @arguments 2>&1
        $exitCode = $LASTEXITCODE

        if ($output) {
            Add-Content `
                -LiteralPath $LogFile `
                -Value ($output | Out-String) `
                -Encoding UTF8
        }

        if ($exitCode -eq 0) {
            Write-Log `
                'System-image backup completed successfully.' `
                'SUCCESS'

            $imagePath = "${backupDrive}:\WindowsImageBackup"
            $backupSize = Get-FolderSize -Path $imagePath
            $backupSizeGB = Convert-BytesToGB -Bytes $backupSize

            Write-Log `
                "Estimated system-image size: $backupSizeGB GB" `
                'INFO'

            Write-Log `
                "System-image location: $imagePath" `
                'SUCCESS'

            $Script:TotalBackupSize += $backupSize
            $Script:BackupsCreated++

            Add-BackupToMetadata `
                -BackupPath $imagePath `
                -BackupType 'SystemImage' `
                -SizeGB $backupSizeGB `
                -Status 'Success'

            return $true
        }

        Write-Log `
            "System-image backup failed with exit code $exitCode." `
            'ERROR'

        return $false
    }
    catch {
        Write-Log `
            "Error creating system image: $($_.Exception.Message)" `
            'ERROR'

        return $false
    }
}

# ============================================================================
# BACKUP LISTING
# ============================================================================

function List-AvailableBackups {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    Write-Log 'AVAILABLE BACKUPS' 'INFO'
    Show-Separator

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        Write-Log `
            "Backup path not found: $BackupPath" `
            'WARNING'

        return
    }

    try {
        $backupDirs = @(Get-ChildItem `
                -LiteralPath $BackupPath `
                -Directory `
                -Force `
                -ErrorAction Stop)

        if ($backupDirs.Count -eq 0) {
            Write-Log 'No backups found.' 'INFO'
            return
        }

        Write-Log `
            "Found $($backupDirs.Count) backup(s):" `
            'INFO'

        foreach ($backup in $backupDirs) {
            $size = Get-FolderSize -Path $backup.FullName
            $sizeGB = Convert-BytesToGB -Bytes $size
            $age = (Get-Date) - $backup.CreationTime

            Write-Log `
                "Backup: $($backup.Name)" `
                'INFO'

            Write-Log `
                " Created: $($backup.CreationTime)" `
                'INFO'

            Write-Log `
                " Age: $($age.Days) days, $($age.Hours) hours" `
                'INFO'

            Write-Log `
                " Size: $sizeGB GB" `
                'INFO'

            Write-Log '' 'INFO'
        }
    }
    catch {
        Write-Log `
            "Error listing backups: $($_.Exception.Message)" `
            'ERROR'
    }
}

# ============================================================================
# RETENTION CLEANUP
# ============================================================================

function Remove-OldBackups {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,

        [Parameter(Mandatory = $true)]
        [int]$RetentionDays
    )

    Write-Log 'MANAGING BACKUP RETENTION' 'INFO'
    Show-Separator

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        Write-Log `
            "Backup path not found: $BackupPath" `
            'WARNING'

        return
    }

    try {
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

        $oldBackups = @(Get-ChildItem `
                -LiteralPath $BackupPath `
                -Directory `
                -Force `
                -ErrorAction Stop |
                Where-Object {
                    $_.CreationTime -lt $cutoffDate
                })

        if ($oldBackups.Count -eq 0) {
            Write-Log `
                "No backups older than $RetentionDays days were found." `
                'SUCCESS'

            return
        }

        Write-Log `
            "Found $($oldBackups.Count) backup(s) older than $RetentionDays days." `
            'WARNING'

        $removedSize = [int64]0

        foreach ($backup in $oldBackups) {
            $size = Get-FolderSize -Path $backup.FullName

            Write-Log `
                "Removing: $($backup.Name)" `
                'INFO'

            try {
                Remove-Item `
                    -LiteralPath $backup.FullName `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop

                $removedSize += $size

                Write-Log `
                    "Deleted: $($backup.FullName)" `
                    'SUCCESS'
            }
            catch {
                Write-Log `
                    "Failed to delete $($backup.FullName): $($_.Exception.Message)" `
                    'ERROR'
            }
        }

        $removedSizeGB = Convert-BytesToGB -Bytes $removedSize

        Write-Log `
            "Cleanup completed. Removed approximately $removedSizeGB GB." `
            'SUCCESS'
    }
    catch {
        Write-Log `
            "Error managing backup retention: $($_.Exception.Message)" `
            'ERROR'
    }
}

# ============================================================================
# REPORT
# ============================================================================

function Show-BackupReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    Write-Log '' 'INFO'
    Show-Separator
    Write-Log 'BACKUP SUMMARY REPORT' 'INFO'
    Show-Separator

    $failureLevel = if ($Script:BackupsFailed -gt 0) {
        'ERROR'
    }
    else {
        'SUCCESS'
    }

    Write-Log `
        "Backups created: $($Script:BackupsCreated)" `
        'SUCCESS'

    Write-Log `
        "Backup failures: $($Script:BackupsFailed)" `
        $failureLevel

    $totalSizeGB = Convert-BytesToGB -Bytes $Script:TotalBackupSize

    Write-Log `
        "Total backup size: $totalSizeGB GB" `
        'INFO'

    Write-Log `
        "Backup location: $BackupPath" `
        'INFO'

    Write-Log `
        "Retention policy: $BackupRetentionDays days" `
        'INFO'

    Write-Log `
        "Log file: $LogFile" `
        'INFO'

    Write-Log `
        "Metadata file: $BackupMetadataFile" `
        'INFO'
}

# ============================================================================
# MAIN
# ============================================================================

function Main {
    Initialize-Logging

    Write-Log ('=' * 72) 'INFO'
    Write-Log 'BACKUP AND RECOVERY SCRIPT' 'INFO'

    Write-Log `
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
        'INFO'

    Write-Log `
        "Log file: $LogFile" `
        'INFO'

    Show-Separator

    $backupDestination = Test-BackupDestination

    if ([string]::IsNullOrWhiteSpace($backupDestination)) {
        Write-Log `
            'Backup cancelled because no destination was specified.' `
            'ERROR'

        return
    }

    Show-Separator
    Write-Log 'PHASE 1: BACKUP CRITICAL USER FILES' 'INFO'
    Show-Separator

    if (-not (Backup-CriticalFiles -BackupPath $backupDestination)) {
        $Script:BackupsFailed++
    }

    Show-Separator
    Write-Log 'PHASE 2: BACKUP WINDOWS REGISTRY' 'INFO'
    Show-Separator

    if (-not (Backup-Registry -BackupPath $backupDestination)) {
        $Script:BackupsFailed++
    }

    Show-Separator
    Write-Log 'PHASE 3: CREATE SYSTEM IMAGE BACKUP' 'INFO'
    Show-Separator

    $createImage = Read-Host 'Create a system image now? (y/n)'

    if ($createImage -match '^(y|yes)$') {
        if (-not (Create-SystemImage -BackupPath $backupDestination)) {
            $Script:BackupsFailed++
        }
    }
    else {
        Write-Log `
            'System-image backup skipped by user.' `
            'INFO'
    }

    Show-Separator
    Write-Log 'PHASE 4: LIST AVAILABLE BACKUPS' 'INFO'
    Show-Separator

    List-AvailableBackups -BackupPath $backupDestination

    Show-Separator
    Write-Log 'PHASE 5: CLEAN UP OLD BACKUPS' 'INFO'
    Show-Separator

    Remove-OldBackups `
        -BackupPath $backupDestination `
        -RetentionDays $BackupRetentionDays

    Show-BackupReport -BackupPath $backupDestination
}

Main

Write-Log `
    "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
    'INFO'

Write-Log `
    "Log saved to: $LogFile" `
    'INFO'

Write-Log `
    "Metadata saved to: $BackupMetadataFile" `
    'INFO'

Write-Log ('=' * 72) 'INFO'
