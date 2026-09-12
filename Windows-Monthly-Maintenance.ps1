<#
.SYNOPSIS
Windows Monthly Maintenance Script

.DESCRIPTION
Runs DISM, SFC, and CHKDSK scans with logging and automated repair attempts.

.NOTES
Requires Administrator privileges.
#>

#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========

$LogPath = "C:\Temp"
$LogFileName = "WindowsMaintenance_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName

$DISMMaxAttempts = 3
$SFCMaxAttempts = 3

$DISMAttempt = 0
$SFCAttempt = 0

$Script:ErrorsFound = $false

# ========== FUNCTIONS ==========

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO" {
            Write-Host $logMessage -ForegroundColor White
        }
        "WARNING" {
            Write-Host $logMessage -ForegroundColor Yellow
        }
        "ERROR" {
            Write-Host $logMessage -ForegroundColor Red
        }
        "SUCCESS" {
            Write-Host $logMessage -ForegroundColor Green
        }
    }

    Add-Content -Path $LogFile -Value $logMessage
}

function Show-Separator {
    Write-Log "================================================================" "INFO"
}

function Start-DISMScan {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Attempt
    )

    Write-Log "===== DISM SCAN (Attempt $Attempt/$DISMMaxAttempts) ====="
    Write-Log "Running: DISM /Online /Cleanup-Image /ScanHealth"

    try {
        $result = & dism.exe /Online /Cleanup-Image /ScanHealth 2>&1
        $exitCode = $LASTEXITCODE
        $output = $result | Out-String

        Add-Content -Path $LogFile -Value $output

        if ($exitCode -ne 0) {
            Write-Log "DISM scan returned exit code $exitCode." "ERROR"
            return "error"
        }

        if ($output -match "component store is repairable") {
            Write-Log "DISM found a repairable component-store problem." "WARNING"
            return "issues_found"
        }

        if ($output -match "No component store corruption detected") {
            Write-Log "DISM scan completed with no corruption detected." "SUCCESS"
            return "no_issues"
        }

        Write-Log "DISM scan completed. Review the log for details." "INFO"
        return "completed"
    }
    catch {
        Write-Log "Error running DISM scan: $($_.Exception.Message)" "ERROR"
        return "error"
    }
}

function Repair-DISMImage {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Attempt
    )

    Write-Log "===== DISM REPAIR (Attempt $Attempt/$DISMMaxAttempts) ====="
    Write-Log "Running: DISM /Online /Cleanup-Image /RestoreHealth"

    try {
        $result = & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1
        $exitCode = $LASTEXITCODE
        $output = $result | Out-String

        Add-Content -Path $LogFile -Value $output

        if ($exitCode -eq 0 -and $output -match "completed successfully") {
            Write-Log "DISM repair completed successfully." "SUCCESS"
            $Script:ErrorsFound = $true
            return "repaired"
        }

        Write-Log "DISM repair returned exit code $exitCode." "ERROR"
        return "error"
    }
    catch {
        Write-Log "Error running DISM repair: $($_.Exception.Message)" "ERROR"
        return "error"
    }
}

function Start-SFCScan {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Attempt
    )

    Write-Log "===== SYSTEM FILE CHECKER SCAN (Attempt $Attempt/$SFCMaxAttempts) ====="
    Write-Log "Running: sfc /scannow"

    try {
        $result = & sfc.exe /scannow 2>&1
        $exitCode = $LASTEXITCODE
        $output = $result | Out-String

        Add-Content -Path $LogFile -Value $output

        if ($output -match "found corrupt files") {
            Write-Log "SFC found corrupt files. A repair was attempted." "WARNING"
            $Script:ErrorsFound = $true
            return "issues_found"
        }

        if ($output -match "did not find any integrity violations") {
            Write-Log "SFC found no integrity violations." "SUCCESS"
            return "no_issues"
        }

        if ($exitCode -ne 0) {
            Write-Log "SFC returned exit code $exitCode." "ERROR"
            return "error"
        }

        Write-Log "SFC scan completed. Review the log for details." "INFO"
        return "completed"
    }
    catch {
        Write-Log "Error running SFC scan: $($_.Exception.Message)" "ERROR"
        return "error"
    }
}

function Start-CHKDSKScan {
    Write-Log "===== CHECK DISK SCAN ====="
    Write-Log "Running: CHKDSK C: /scan"
    Write-Log "This scan checks the disk online but does not normally repair errors." "WARNING"

    try {
        $result = & chkdsk.exe C: /scan 2>&1
        $exitCode = $LASTEXITCODE
        $output = $result | Out-String

        Add-Content -Path $LogFile -Value $output

        if ($output -match "Windows has scanned the file system and found problems") {
            Write-Log "CHKDSK found disk errors." "WARNING"
            $Script:ErrorsFound = $true

            Write-Log "To schedule repairs, run: CHKDSK C: /F" "INFO"
            Write-Log "A system restart may be required." "WARNING"

            return "issues_found"
        }

        if ($exitCode -ne 0) {
            Write-Log "CHKDSK returned exit code $exitCode." "ERROR"
            return "error"
        }

        Write-Log "CHKDSK completed with no reported errors." "SUCCESS"
        return "no_issues"
    }
    catch {
        Write-Log "Error running CHKDSK: $($_.Exception.Message)" "ERROR"
        return "error"
    }
}

function Main {
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }

    Write-Log "WINDOWS MONTHLY MAINTENANCE SCRIPT"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Log file: $LogFile"
    Show-Separator

    # ========== PHASE 1: DISM ==========

    Write-Log "PHASE 1: DISM IMAGE SERVICING"
    Show-Separator

    while ($DISMAttempt -lt $DISMMaxAttempts) {
        $DISMAttempt++

        $scanResult = Start-DISMScan -Attempt $DISMAttempt

        if ($scanResult -eq "issues_found") {
            $repairResult = Repair-DISMImage -Attempt $DISMAttempt

            if ($repairResult -eq "error") {
                Write-Log "DISM repair failed. Stopping DISM phase." "ERROR"
                break
            }

            continue
        }

        break
    }

    # ========== PHASE 2: SFC ==========

    Write-Log "PHASE 2: SYSTEM FILE CHECKER"
    Show-Separator

    while ($SFCAttempt -lt $SFCMaxAttempts) {
        $SFCAttempt++

        $sfcResult = Start-SFCScan -Attempt $SFCAttempt

        if ($sfcResult -eq "issues_found" -and $SFCAttempt -lt $SFCMaxAttempts) {
            Write-Log "Waiting 30 seconds before the next SFC scan." "INFO"
            Start-Sleep -Seconds 30
        }
        else {
            break
        }
    }

    # ========== PHASE 3: CHKDSK ==========

    Write-Log "PHASE 3: CHECK DISK"
    Show-Separator

    $null = Start-CHKDSKScan

    # ========== SUMMARY ==========

    Show-Separator
    Write-Log "MAINTENANCE SUMMARY"
    Show-Separator

    if ($Script:ErrorsFound) {
        Write-Log "Status: ERRORS FOUND OR REPAIRS PERFORMED" "WARNING"
        Write-Log "A system restart may be recommended." "WARNING"
    }
    else {
        Write-Log "Status: NO ERRORS FOUND" "SUCCESS"
        Write-Log "The system passed all maintenance checks." "SUCCESS"
    }

    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Log file saved to: $LogFile"
    Show-Separator
}

# ========== RUN SCRIPT ==========

Main

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
