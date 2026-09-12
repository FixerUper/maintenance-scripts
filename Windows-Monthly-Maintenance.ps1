<#
.SYNOPSIS
    Windows Monthly Maintenance Script

.DESCRIPTION
    Runs:
      1. DISM /CheckHealth
      2. DISM /RestoreHealth if required
      3. DISM /CheckHealth verification
      4. SFC /scannow
      5. CHKDSK C: /scan

.NOTES
    Run from an elevated PowerShell window.

.EXAMPLE
    .\WindowsMonthlyMaintenance.ps1

.EXAMPLE
    .\WindowsMonthlyMaintenance.ps1 -PauseAtEnd
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$PauseAtEnd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

$LogDirectory = "C:\Temp"

$LogFileName = "WindowsMaintenance_{0}.log" -f `
    (Get-Date -Format "yyyyMMdd_HHmmss")

$LogFile = Join-Path `
    -Path $LogDirectory `
    -ChildPath $LogFileName

# Script status flags
$Script:ErrorsFound = $false
$Script:RepairsPerformed = $false

# ============================================================================
# LOGGING
# ============================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[{0}] [{1}] {2}" -f `
        $Timestamp,
        $Level,
        $Message

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

    Add-Content `
        -LiteralPath $LogFile `
        -Value $LogMessage `
        -Encoding UTF8
}

function Write-Separator {
    Write-Log "================================================================"
}

function Write-CommandOutput {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output
    )

    if (-not [string]::IsNullOrWhiteSpace($Output)) {
        Add-Content `
            -LiteralPath $LogFile `
            -Value $Output `
            -Encoding UTF8
    }
}

# ============================================================================
# DISM /CHECKHEALTH
# ============================================================================

function Invoke-DISMCheckHealth {
    [CmdletBinding()]
    param(
        [string]$Description = "DISM component-store check"
    )

    Write-Log "===== $Description ====="
    Write-Log "Running: DISM.exe /Online /Cleanup-Image /CheckHealth"

    try {
        $CommandOutput = @(
            & DISM.exe /Online /Cleanup-Image /CheckHealth 2>&1
        )

        $ExitCode = $LASTEXITCODE
        $Output = $CommandOutput -join [Environment]::NewLine

        Write-CommandOutput $Output

        if ($ExitCode -ne 0) {
            Write-Log "DISM /CheckHealth returned exit code $ExitCode." "ERROR"
            $Script:ErrorsFound = $true
            return "error"
        }

        # English Windows output:
        # "The component store is repairable."
        if (
            $Output -match "component store is repairable" -or
            $Output -match "component store corruption can be repaired"
        ) {
            Write-Log "DISM reports that the component store is repairable." "WARNING"
            $Script:ErrorsFound = $true
            return "repair_required"
        }

        # English Windows output:
        # "No component store corruption detected."
        if (
            $Output -match "No component store corruption detected" -or
            $Output -match "component store corruption was not detected"
        ) {
            Write-Log "DISM reports no recorded component-store corruption." "SUCCESS"
            return "healthy"
        }

        Write-Log "DISM /CheckHealth completed, but the result was not recognised." "WARNING"
        Write-Log "Review the DISM output in the log file." "WARNING"

        # Do not repeatedly repair when the output cannot be interpreted.
        return "completed"
    }
    catch {
        Write-Log "Error running DISM /CheckHealth: $($_.Exception.Message)" "ERROR"
        $Script:ErrorsFound = $true
        return "error"
    }
}

# ============================================================================
# DISM /RESTOREHEALTH
# ============================================================================

function Invoke-DISMRepair {
    Write-Log "===== DISM COMPONENT-STORE REPAIR ====="
    Write-Log "Running: DISM.exe /Online /Cleanup-Image /RestoreHealth"

    try {
        $CommandOutput = @(
            & DISM.exe /Online /Cleanup-Image /RestoreHealth 2>&1
        )

        $ExitCode = $LASTEXITCODE
        $Output = $CommandOutput -join [Environment]::NewLine

        Write-CommandOutput $Output

        if ($ExitCode -eq 0) {
            Write-Log "DISM repair completed successfully." "SUCCESS"
            $Script:RepairsPerformed = $true
            return "repaired"
        }

        Write-Log "DISM repair returned exit code $ExitCode." "ERROR"
        $Script:ErrorsFound = $true
        return "error"
    }
    catch {
        Write-Log "Error running DISM repair: $($_.Exception.Message)" "ERROR"
        $Script:ErrorsFound = $true
        return "error"
    }
}

# ============================================================================
# DISM PHASE
# ============================================================================

function Invoke-DISMPhase {
    Write-Log "PHASE 1: DISM IMAGE SERVICING"
    Write-Separator

    $InitialResult = Invoke-DISMCheckHealth `
        -Description "DISM INITIAL CHECK"

    switch ($InitialResult) {
        "healthy" {
            Write-Log "DISM phase completed. No repair is required." "SUCCESS"
        }

        "completed" {
            Write-Log "DISM completed, but no repair decision could be made." "WARNING"
        }

        "repair_required" {
            Write-Log "DISM reports that repair is required." "WARNING"

            $RepairResult = Invoke-DISMRepair

            if ($RepairResult -eq "repaired") {
                Write-Log "Verifying DISM repair with /CheckHealth." "INFO"

                $VerificationResult = Invoke-DISMCheckHealth `
                    -Description "DISM REPAIR VERIFICATION"

                switch ($VerificationResult) {
                    "healthy" {
                        Write-Log "DISM repair verification passed." "SUCCESS"
                    }

                    "repair_required" {
                        Write-Log `
                            "DISM still reports that the component store is repairable." `
                            "ERROR"

                        $Script:ErrorsFound = $true
                    }

                    "completed" {
                        Write-Log `
                            "DISM verification completed, but the result was not recognised." `
                            "WARNING"
                    }

                    "error" {
                        Write-Log "DISM verification failed." "ERROR"
                        $Script:ErrorsFound = $true
                    }
                }
            }
            else {
                Write-Log "DISM repair failed. No further DISM repair attempts will be made." "ERROR"
                $Script:ErrorsFound = $true
            }
        }

        "error" {
            Write-Log "Initial DISM check failed." "ERROR"
            $Script:ErrorsFound = $true
        }

        default {
            Write-Log "Unexpected DISM result: $InitialResult" "ERROR"
            $Script:ErrorsFound = $true
        }
    }

    Write-Separator
}

# ============================================================================
# SFC PHASE
# ============================================================================

function Invoke-SFCScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Attempt
    )

    Write-Log "===== SFC SCAN (Attempt $Attempt/2) ====="
    Write-Log "Running: SFC.exe /scannow"

    try {
        $CommandOutput = @(
            & SFC.exe /scannow 2>&1
        )

        $ExitCode = $LASTEXITCODE
        $Output = $CommandOutput -join [Environment]::NewLine

        Write-CommandOutput $Output

        if ($Output -match "did not find any integrity violations") {
            Write-Log "SFC found no integrity violations." "SUCCESS"
            return "healthy"
        }

        if (
            $Output -match `
                "found corrupt files and successfully repaired them"
        ) {
            Write-Log "SFC found corrupt files and repaired them." "WARNING"
            $Script:ErrorsFound = $true
            $Script:RepairsPerformed = $true
            return "repaired"
        }

        if (
            $Output -match `
                "found corrupt files but was unable to fix some"
        ) {
            Write-Log `
                "SFC found corrupt files but could not repair some of them." `
                "ERROR"

            $Script:ErrorsFound = $true
            return "unrepaired"
        }

        if ($Output -match "found corrupt files") {
            Write-Log "SFC found corrupt files." "WARNING"
            $Script:ErrorsFound = $true
            return "issues_found"
        }

        if ($ExitCode -ne 0) {
            Write-Log "SFC returned exit code $ExitCode." "ERROR"
            $Script:ErrorsFound = $true
            return "error"
        }

        Write-Log `
            "SFC completed, but its result was not recognised." `
            "WARNING"

        Write-Log "Review the SFC output in the log file." "WARNING"
        return "completed"
    }
    catch {
        Write-Log "Error running SFC: $($_.Exception.Message)" "ERROR"
        $Script:ErrorsFound = $true
        return "error"
    }
}

function Invoke-SFCPhase {
    Write-Log "PHASE 2: SYSTEM FILE CHECKER"
    Write-Separator

    $FirstResult = Invoke-SFCScan -Attempt 1

    switch ($FirstResult) {
        "healthy" {
            Write-Log "SFC phase completed successfully." "SUCCESS"
        }

        "repaired" {
            Write-Log "Running one SFC verification scan." "INFO"
            Start-Sleep -Seconds 30

            $VerificationResult = Invoke-SFCScan -Attempt 2

            if ($VerificationResult -eq "healthy") {
                Write-Log "SFC repair verification passed." "SUCCESS"
            }
            elseif ($VerificationResult -eq "repaired") {
                Write-Log "SFC repaired additional files during verification." "WARNING"
            }
            else {
                Write-Log "SFC verification did not report a clean result." "ERROR"
                $Script:ErrorsFound = $true
            }
        }

        "issues_found" {
            Write-Log "Running one follow-up SFC scan." "INFO"
            Start-Sleep -Seconds 30

            $VerificationResult = Invoke-SFCScan -Attempt 2

            if ($VerificationResult -eq "healthy") {
                Write-Log "SFC follow-up scan found no remaining issues." "SUCCESS"
            }
            else {
                Write-Log "SFC still reports possible file corruption." "ERROR"
                $Script:ErrorsFound = $true
            }
        }

        "unrepaired" {
            Write-Log "SFC could not repair all detected files." "ERROR"
            Write-Log "Review CBS.log for additional details." "INFO"
        }

        "completed" {
            Write-Log "SFC completed without a recognised result." "WARNING"
        }

        "error" {
            Write-Log "SFC failed." "ERROR"
        }

        default {
            Write-Log "Unexpected SFC result: $FirstResult" "ERROR"
            $Script:ErrorsFound = $true
        }
    }

    Write-Separator
}

# ============================================================================
# CHKDSK PHASE
# ============================================================================

function Invoke-CHKDSKPhase {
    Write-Log "PHASE 3: CHECK DISK"
    Write-Separator

    Write-Log "===== CHKDSK ONLINE SCAN ====="
    Write-Log "Running: CHKDSK.exe C: /scan"
    Write-Log "This scan normally does not repair errors." "INFO"

    try {
        $CommandOutput = @(
            & CHKDSK.exe C: /scan 2>&1
        )

        $ExitCode = $LASTEXITCODE
        $Output = $CommandOutput -join [Environment]::NewLine

        Write-CommandOutput $Output

        if (
            $Output -match "found problems" -or
            $Output -match "found errors" -or
            $Output -match "errors found"
        ) {
            Write-Log "CHKDSK found disk or file-system errors." "WARNING"
            $Script:ErrorsFound = $true

            Write-Log "To schedule repairs, run:" "INFO"
            Write-Log "CHKDSK C: /F" "INFO"
            Write-Log "A restart may be required." "WARNING"

            return
        }

        if ($ExitCode -ne 0) {
            Write-Log "CHKDSK returned exit code $ExitCode." "ERROR"
            $Script:ErrorsFound = $true
            return
        }

        Write-Log "CHKDSK completed with no reported errors." "SUCCESS"
    }
    catch {
        Write-Log "Error running CHKDSK: $($_.Exception.Message)" "ERROR"
        $Script:ErrorsFound = $true
    }

    Write-Separator
}

# ============================================================================
# MAIN
# ============================================================================

function Main {
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $LogDirectory `
            -Force | Out-Null
    }

    Write-Log "WINDOWS MONTHLY MAINTENANCE SCRIPT"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Log file: $LogFile"
    Write-Separator

    try {
        Invoke-DISMPhase
        Invoke-SFCPhase
        Invoke-CHKDSKPhase
    }
    catch {
        Write-Log "Unexpected script error: $($_.Exception.Message)" "ERROR"
        $Script:ErrorsFound = $true
    }
    finally {
        Write-Separator
        Write-Log "MAINTENANCE SUMMARY"

        if ($Script:RepairsPerformed) {
            Write-Log "Repairs were performed." "WARNING"
        }
        else {
            Write-Log "No repairs were performed." "INFO"
        }

        if ($Script:ErrorsFound) {
            Write-Log "Status: ERRORS OR UNRESOLVED ISSUES FOUND" "WARNING"
            Write-Log "Review the log file: $LogFile" "WARNING"
        }
        else {
            Write-Log "Status: NO ERRORS FOUND" "SUCCESS"
        }

        Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Separator
    }
}

# ============================================================================
# START
# ============================================================================

Main

if ($PauseAtEnd) {
    Write-Host ""
    Read-Host "Press Enter to exit"
}
