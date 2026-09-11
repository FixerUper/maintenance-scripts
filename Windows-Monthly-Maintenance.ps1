<#
.SYNOPSIS
    Windows Monthly Maintenance Script
    Runs DISM, SFC, and CHKDSK scans with automated repair and logging

.DESCRIPTION
    This script performs comprehensive system maintenance including:
    - DISM online image servicing (scan and repair)
    - System File Checker (SFC) scans with repeat logic if errors found
    - CHKDSK disk check and error reporting
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Log file: $env:USERPROFILE\Documents\WindowsMaintenance_YYYYMMDD_HHmmss.log

.AUTHOR
    Maintenance Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "WindowsMaintenance_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$DISMMaxAttempts = 3
$SFCMaxAttempts = 3
$DISMAttempt = 0
$SFCAttempt = 0
$Script:ErrorsFound = $false

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

function Start-DISMScan {
    <#
    .SYNOPSIS
        Run DISM online image scan
    #>
    param(
        [int]$Attempt
    )
    
    Write-Log "===== DISM SCAN (Attempt $Attempt/$DISMMaxAttempts) =====" "INFO"
    Write-Log "Running: DISM /Online /Cleanup-Image /ScanHealth" "INFO"
    
    try {
        $result = & dism /Online /Cleanup-Image /ScanHealth 2>&1
        $output = $result | Out-String
        Add-Content -Path $LogFile -Value $output
        
        if ($output -match "found") {
            Write-Log "DISM scan found issues. Proceeding with repair..." "WARNING"
            return "issues_found"
        } elseif ($output -match "successful") {
            Write-Log "DISM scan completed successfully with no issues found." "SUCCESS"
            return "no_issues"
        } else {
            Write-Log "DISM scan completed." "INFO"
            return "completed"
        }
    }
    catch {
        Write-Log "Error running DISM scan: $_" "ERROR"
        return "error"
    }
}

function Repair-DISMImage {
    <#
    .SYNOPSIS
        Run DISM online image repair
    #>
    param(
        [int]$Attempt
    )
    
    Write-Log "===== DISM REPAIR (Attempt $Attempt/$DISMMaxAttempts) =====" "INFO"
    Write-Log "Running: DISM /Online /Cleanup-Image /RestoreHealth" "INFO"
    
    try {
        $result = & dism /Online /Cleanup-Image /RestoreHealth 2>&1
        $output = $result | Out-String
        Add-Content -Path $LogFile -Value $output
        
        if ($output -match "successfully repaired" -or $output -match "The operation completed successfully") {
            Write-Log "DISM repair completed successfully." "SUCCESS"
            $Script:ErrorsFound = $true
            return "repaired"
        } else {
            Write-Log "DISM repair process completed." "INFO"
            return "completed"
        }
    }
    catch {
        Write-Log "Error running DISM repair: $_" "ERROR"
        return "error"
    }
}

function Start-SFCScan {
    <#
    .SYNOPSIS
        Run System File Checker scan
    #>
    param(
        [int]$Attempt
    )
    
    Write-Log "===== SYSTEM FILE CHECKER SCAN (Attempt $Attempt/$SFCMaxAttempts) =====" "INFO"
    Write-Log "Running: sfc /scannow" "INFO"
    
    try {
        $result = & sfc /scannow 2>&1
        $output = $result | Out-String
        Add-Content -Path $LogFile -Value $output
        
        if ($output -match "found corrupt") {
            Write-Log "SFC found corrupt files. Will repeat scan after repair." "WARNING"
            $Script:ErrorsFound = $true
            return "issues_found"
        } elseif ($output -match "not found any integrity violations") {
            Write-Log "SFC scan completed. No integrity violations found." "SUCCESS"
            return "no_issues"
        } else {
            Write-Log "SFC scan completed." "INFO"
            return "completed"
        }
    }
    catch {
        Write-Log "Error running SFC scan: $_" "ERROR"
        return "error"
    }
}

function Start-CHKDSKScan {
    <#
    .SYNOPSIS
        Run Check Disk scan (read-only by default)
    #>
    
    Write-Log "===== CHECK DISK SCAN =====" "INFO"
    Write-Log "Running: chkdsk C: /scan" "INFO"
    Write-Log "Note: This scan will not repair errors without /repair flag. To enable repairs, the drive must be scheduled for next boot." "WARNING"
    
    try {
        $result = & chkdsk C: /scan 2>&1
        $output = $result | Out-String
        Add-Content -Path $LogFile -Value $output
        
        if ($output -match "errors" -or $output -match "bad") {
            Write-Log "CHKDSK found disk errors. Review log for details." "WARNING"
            $Script:ErrorsFound = $true
            
            # Ask user if they want to schedule repair at next boot
            Write-Log "" "INFO"
            Write-Log "CHKDSK requires administrator scheduling for repairs at next boot." "WARNING"
            Write-Log "To schedule repairs, you would need to run: chkdsk C: /F" "INFO"
            Write-Log "This requires a system restart." "WARNING"
            Write-Log "" "INFO"
            
            return "issues_found"
        } else {
            Write-Log "CHKDSK scan completed. No errors detected." "SUCCESS"
            return "no_issues"
        }
    }
    catch {
        Write-Log "Error running CHKDSK scan: $_" "ERROR"
        return "error"
    }
}

function Show-Separator {
    <#
    .SYNOPSIS
        Display a visual separator in logs
    #>
    Write-Log "================================================================" "INFO"
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "WINDOWS MONTHLY MAINTENANCE SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: DISM SCAN AND REPAIR =====
    Write-Log "PHASE 1: DISM IMAGE SERVICING" "INFO"
    Show-Separator
    
    while ($DISMAttempt -lt $DISMMaxAttempts) {
        $DISMAttempt++
        $scanResult = Start-DISMScan -Attempt $DISMAttempt
        
        if ($scanResult -eq "issues_found") {
            Write-Log "" "INFO"
            $repairResult = Repair-DISMImage -Attempt $DISMAttempt
            Write-Log "" "INFO"
            
            if ($repairResult -eq "error") {
                Write-Log "DISM repair failed. Stopping DISM phase." "ERROR"
                break
            }
        } elseif ($scanResult -eq "no_issues" -or $scanResult -eq "error") {
            break
        }
        
        Write-Log "" "INFO"
    }
    
    Show-Separator
    
    # ===== PHASE 2: SYSTEM FILE CHECKER =====
    Write-Log "PHASE 2: SYSTEM FILE CHECKER (SFC)" "INFO"
    Show-Separator
    
    while ($SFCAttempt -lt $SFCMaxAttempts) {
        $SFCAttempt++
        $sfcResult = Start-SFCScan -Attempt $SFCAttempt
        
        if ($sfcResult -eq "issues_found") {
            Write-Log "Corrupt files detected. SFC will attempt repair automatically." "WARNING"
            Write-Log "Waiting 30 seconds before next scan..." "INFO"
            Start-Sleep -Seconds 30
            Write-Log "" "INFO"
        } else {
            break
        }
    }
    
    Show-Separator
    
    # ===== PHASE 3: CHECK DISK =====
    Write-Log "PHASE 3: CHECK DISK (CHKDSK)" "INFO"
    Show-Separator
    
    $chkdskResult = Start-CHKDSKScan
    
    Show-Separator
    
    # ===== COMPLETION SUMMARY =====
    Write-Log "MAINTENANCE SUMMARY" "INFO"
    Show-Separator
    
    if ($Script:ErrorsFound) {
        Write-Log "Status: ERRORS FOUND AND REPAIRED" "WARNING"
        Write-Log "The system performed repairs during this maintenance run." "WARNING"
        Write-Log "A system restart is recommended to complete any pending repairs." "WARNING"
    } else {
        Write-Log "Status: NO ERRORS FOUND" "SUCCESS"
        Write-Log "Your system passed all maintenance checks." "SUCCESS"
    }
    
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
