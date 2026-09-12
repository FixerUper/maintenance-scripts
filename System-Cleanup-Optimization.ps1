<#
.SYNOPSIS
    System Cleanup and Optimization Script

.DESCRIPTION
    Removes temporary files, clears caches, empties the Recycle Bin,
    removes old log files, optionally disables selected startup entries,
    compacts the OS installation, and reports disk space freed.

.NOTES
    Requires Administrator privileges.
    Log files are saved to C:\Temp.

    Review the startup application list before running.
#>

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ============================================================
# CONFIGURATION
# ============================================================

$LogPath = "C:\Temp"

$LogFileName = "SystemCleanup_{0}.log" -f (
    Get-Date -Format "yyyyMMdd_HHmmss"
)

$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName

$Script:TotalSpaceFreed = [int64]0
$Script:FilesDeleted = 0
$Script:StartupItemsDisabled = 0

$CleanupLocations = @(
    @{
        Path = $env:TEMP
        Name = "User Temp"
    },
    @{
        Path = "$env:SystemRoot\Temp"
        Name = "System Temp"
    },
    @{
        Path = "$env:SystemRoot\Prefetch"
        Name = "Prefetch"
    },
    @{
        Path = "$env:LOCALAPPDATA\Temp"
        Name = "Local AppData Temp"
    },
    @{
        Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
        Name = "Internet Cache"
    }
)

# These are registry value names under the current user's Run key.
# Remove any item you do not want this script to disable.
$StartupItems = @(
    "OneDrive",
    "Skype",
    "CCleaner",
    "Discord",
    "Spotify",
    "Steam"
)

# ============================================================
# FUNCTIONS
# ============================================================

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

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

    Add-Content -Path $LogFile -Value $LogMessage -Encoding UTF8
}

function Show-Separator {
    Write-Log "================================================================" "INFO"
}

function Convert-BytesToGB {
    param(
        [AllowNull()]
        [int64]$Bytes
    )

    if ($null -eq $Bytes -or $Bytes -le 0) {
        return 0
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

    $Size = Get-ChildItem `
        -LiteralPath $Path `
        -Force `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum

    if ($null -eq $Size.Sum) {
        return [int64]0
    }

    return [int64]$Size.Sum
}

function Remove-TempFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$LocationName
    )

    Write-Log "Cleaning: $LocationName" "INFO"

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Path not found: $Path" "WARNING"
        return
    }

    $BeforeSize = Get-FolderSize -Path $Path
    $DeletedCount = 0

    try {
        # Delete files first.
        $Files = Get-ChildItem `
            -LiteralPath $Path `
            -Force `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue

        foreach ($File in $Files) {
            try {
                $FileSize = $File.Length

                Remove-Item `
                    -LiteralPath $File.FullName `
                    -Force `
                    -ErrorAction Stop

                $DeletedCount++
                $Script:FilesDeleted++
            }
            catch {
                Write-Log "Skipped locked or protected file: $($File.FullName)" "WARNING"
            }
        }

        # Remove empty directories. The root directory itself is preserved.
        $Directories = Get-ChildItem `
            -LiteralPath $Path `
            -Force `
            -Recurse `
            -Directory `
            -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending

        foreach ($Directory in $Directories) {
            try {
                Remove-Item `
                    -LiteralPath $Directory.FullName `
                    -Force `
                    -ErrorAction Stop
            }
            catch {
                # The directory may not be empty or may be in use.
            }
        }

        $AfterSize = Get-FolderSize -Path $Path
        $SpaceFreed = [math]::Max(0, $BeforeSize - $AfterSize)

        if ($SpaceFreed -gt 0) {
            $FreedGB = Convert-BytesToGB -Bytes $SpaceFreed

            Write-Log `
                "Freed: $FreedGB GB | Files deleted: $DeletedCount" `
                "SUCCESS"

            $Script:TotalSpaceFreed += $SpaceFreed
        }
        else {
            Write-Log `
                "No removable files found or files were in use" `
                "SUCCESS"
        }
    }
    catch {
        Write-Log "Error cleaning $LocationName`: $($_.Exception.Message)" "ERROR"
    }
}

function Clear-RecycleBinSafely {
    Write-Log "Emptying Recycle Bin..." "INFO"

    try {
        if (Get-Command -Name Clear-RecycleBin -ErrorAction SilentlyContinue) {
            Clear-RecycleBin `
                -DriveLetter C `
                -Force `
                -ErrorAction Stop

            Write-Log "Recycle Bin emptied successfully" "SUCCESS"
        }
        else {
            $Shell = New-Object -ComObject Shell.Application
            $RecycleBin = $Shell.Namespace(10)

            if ($null -ne $RecycleBin) {
                $RecycleBin.Self.InvokeVerb("empty")
                Write-Log "Recycle Bin emptied successfully" "SUCCESS"
            }
            else {
                Write-Log "Recycle Bin could not be accessed" "WARNING"
            }
        }
    }
    catch {
        Write-Log "Error emptying Recycle Bin: $($_.Exception.Message)" "ERROR"
    }
}

function Clear-WindowsUpdateCache {
    Write-Log "Clearing Windows Update cache..." "INFO"

    $UpdatePath = Join-Path `
        -Path $env:SystemRoot `
        -ChildPath "SoftwareDistribution\Download"

    if (-not (Test-Path -LiteralPath $UpdatePath)) {
        Write-Log "Windows Update cache was not found" "SUCCESS"
        return
    }

    $BeforeSize = Get-FolderSize -Path $UpdatePath
    $DeletedCount = 0

    try {
        $Items = Get-ChildItem `
            -LiteralPath $UpdatePath `
            -Force `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending

        foreach ($Item in $Items) {
            try {
                Remove-Item `
                    -LiteralPath $Item.FullName `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop

                if (-not $Item.PSIsContainer) {
                    $DeletedCount++
                    $Script:FilesDeleted++
                }
            }
            catch {
                Write-Log "Skipped Windows Update item: $($Item.FullName)" "WARNING"
            }
        }

        $AfterSize = Get-FolderSize -Path $UpdatePath
        $SpaceFreed = [math]::Max(0, $BeforeSize - $AfterSize)

        if ($SpaceFreed -gt 0) {
            $FreedGB = Convert-BytesToGB -Bytes $SpaceFreed

            Write-Log `
                "Freed: $FreedGB GB from Windows Update cache | Files deleted: $DeletedCount" `
                "SUCCESS"

            $Script:TotalSpaceFreed += $SpaceFreed
        }
        else {
            Write-Log "Windows Update cache was already clean or files were in use" "SUCCESS"
        }
    }
    catch {
        Write-Log "Error clearing Windows Update cache: $($_.Exception.Message)" "ERROR"
    }
}

function Remove-OldLogFiles {
    param(
        [int]$OlderThanDays = 30
    )

    Write-Log "Removing log files older than $OlderThanDays days..." "INFO"

    $LogLocations = @(
        "$env:SystemRoot\System32\winevt\Logs",
        "$env:SystemRoot\Logs"
    )

    $CutoffDate = (Get-Date).AddDays(-$OlderThanDays)
    $LogsDeleted = 0
    $SpaceFreed = [int64]0

    foreach ($LogLocation in $LogLocations) {
        if (-not (Test-Path -LiteralPath $LogLocation)) {
            continue
        }

        try {
            $OldLogs = Get-ChildItem `
                -LiteralPath $LogLocation `
                -Filter "*.log" `
                -File `
                -Force `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.LastWriteTime -lt $CutoffDate
                }

            foreach ($OldLog in $OldLogs) {
                try {
                    $FileSize = $OldLog.Length

                    Remove-Item `
                        -LiteralPath $OldLog.FullName `
                        -Force `
                        -ErrorAction Stop

                    $SpaceFreed += $FileSize
                    $LogsDeleted++
                    $Script:FilesDeleted++
                }
                catch {
                    Write-Log "Skipped protected log: $($OldLog.FullName)" "WARNING"
                }
            }
        }
        catch {
            Write-Log "Could not scan log directory: $LogLocation" "WARNING"
        }
    }

    if ($LogsDeleted -gt 0) {
        $FreedGB = Convert-BytesToGB -Bytes $SpaceFreed

        Write-Log `
            "Deleted $LogsDeleted old log files | Freed: $FreedGB GB" `
            "SUCCESS"

        $Script:TotalSpaceFreed += $SpaceFreed
    }
    else {
        Write-Log "No old log files were removed" "SUCCESS"
    }
}

function Disable-StartupBloat {
    Write-Log "Checking selected startup applications..." "INFO"

    $RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $DisabledCount = 0

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        Write-Log "Startup registry key was not found" "WARNING"
        return
    }

    foreach ($StartupItem in $StartupItems) {
        try {
            $ExistingItem = Get-ItemProperty `
                -Path $RegistryPath `
                -Name $StartupItem `
                -ErrorAction SilentlyContinue

            if ($null -ne $ExistingItem) {
                Remove-ItemProperty `
                    -Path $RegistryPath `
                    -Name $StartupItem `
                    -Force `
                    -ErrorAction Stop

                Write-Log "Disabled startup item: $StartupItem" "SUCCESS"

                $DisabledCount++
                $Script:StartupItemsDisabled++
            }
        }
        catch {
            Write-Log `
                "Could not disable startup item $StartupItem`: $($_.Exception.Message)" `
                "WARNING"
        }
    }

    if ($DisabledCount -eq 0) {
        Write-Log "No selected startup applications were found" "SUCCESS"
    }
    else {
        Write-Log "Disabled $DisabledCount startup application(s)" "SUCCESS"
    }
}

function Compact-OSInstallation {
    Write-Log "Compacting OS installation..." "INFO"
    Write-Log "This may take several minutes..." "WARNING"

    try {
        $CompactOutput = & compact.exe /compactos:always 2>&1

        Add-Content `
            -Path $LogFile `
            -Value ($CompactOutput | Out-String) `
            -Encoding UTF8

        if ($LASTEXITCODE -eq 0) {
            Write-Log "OS compaction completed successfully" "SUCCESS"
        }
        else {
            Write-Log "OS compaction returned exit code $LASTEXITCODE" "WARNING"
        }
    }
    catch {
        Write-Log "Error compacting OS: $($_.Exception.Message)" "ERROR"
    }
}

function Show-CleanupReport {
    $TotalGB = Convert-BytesToGB -Bytes $Script:TotalSpaceFreed

    Write-Log "" "INFO"
    Show-Separator
    Write-Log "SYSTEM CLEANUP SUMMARY REPORT" "INFO"
    Show-Separator

    Write-Log "Total space freed: $TotalGB GB" "SUCCESS"
    Write-Log "Files deleted: $($Script:FilesDeleted)" "SUCCESS"
    Write-Log "Startup items disabled: $($Script:StartupItemsDisabled)" "SUCCESS"
    Write-Log "Log file: $LogFile" "INFO"

    Show-Separator
}

# ============================================================
# MAIN EXECUTION
# ============================================================

function Main {
    try {
        if (-not (Test-Path -LiteralPath $LogPath)) {
            New-Item `
                -ItemType Directory `
                -Path $LogPath `
                -Force `
                -ErrorAction Stop |
                Out-Null
        }

        # Create the log before the first Write-Log call.
        New-Item `
            -ItemType File `
            -Path $LogFile `
            -Force `
            -ErrorAction Stop |
            Out-Null

        Write-Log "SYSTEM CLEANUP AND OPTIMIZATION SCRIPT" "INFO"
        Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
        Write-Log "Log location: $LogFile" "INFO"
        Show-Separator

        Write-Log "PHASE 1: REMOVE TEMPORARY FILES" "INFO"
        Show-Separator

        foreach ($Location in $CleanupLocations) {
            Write-Log "" "INFO"

            Remove-TempFiles `
                -Path $Location.Path `
                -LocationName $Location.Name
        }

        Write-Log "" "INFO"
        Show-Separator

        Write-Log "PHASE 2: EMPTY RECYCLE BIN" "INFO"
        Show-Separator
        Clear-RecycleBinSafely

        Write-Log "" "INFO"
        Show-Separator

        Write-Log "PHASE 3: CLEAR WINDOWS UPDATE CACHE" "INFO"
        Show-Separator
        Clear-WindowsUpdateCache

        Write-Log "" "INFO"
        Show-Separator

        Write-Log "PHASE 4: REMOVE OLD LOG FILES" "INFO"
        Show-Separator
        Remove-OldLogFiles -OlderThanDays 30

        Write-Log "" "INFO"
        Show-Separator

        Write-Log "PHASE 5: DISABLE SELECTED STARTUP APPLICATIONS" "INFO"
        Show-Separator
        Disable-StartupBloat

        Write-Log "" "INFO"
        Show-Separator

        Write-Log "PHASE 6: COMPACT OS INSTALLATION" "INFO"
        Show-Separator
        Compact-OSInstallation

        Write-Log "" "INFO"
        Show-CleanupReport

        Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
        Write-Log "Log file saved to: $LogFile" "INFO"
        Show-Separator
    }
    catch {
        Write-Host "Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Main
