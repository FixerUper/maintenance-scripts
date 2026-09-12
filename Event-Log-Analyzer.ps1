<#
.SYNOPSIS
    Event Log Analyzer Script

.DESCRIPTION
    Analyzes Windows System, Security, and Application event logs for:
    - Errors and warnings
    - Failed and successful logons
    - System crashes
    - Windows service failures
    - Common error sources

    Results are written to C:\temp.

.NOTES
    Requires Administrator privileges.
#>

#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========

$LogPath = 'C:\temp'

$TimeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$LogFile = Join-Path -Path $LogPath -ChildPath "EventLogAnalysis_$TimeStamp.log"
$ReportFile = Join-Path -Path $LogPath -ChildPath "EventLogReport_$TimeStamp.html"
$CSVExportFile = Join-Path -Path $LogPath -ChildPath "EventLogExport_$TimeStamp.csv"

$DaysToAnalyze = 7
$MaxEventsToAnalyze = 10000

$Script:CriticalErrorsCount = 0
$Script:WarningsCount = 0
$Script:InfoCount = 0
$Script:SuccessAuditCount = 0

# Create output directory if required
if (-not (Test-Path -LiteralPath $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# ========== FUNCTIONS ==========

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
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

    Add-Content -LiteralPath $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Show-Separator {
    Write-Log '================================================================' 'INFO'
}

function Analyze-SystemLog {
    Write-Log 'ANALYZING SYSTEM EVENT LOG' 'INFO'
    Show-Separator

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        Write-Log "Analyzing System events from the last $DaysToAnalyze days..." 'INFO'
        Write-Log '' 'INFO'

        $systemEvents = @(
            Get-EventLog `
                -LogName System `
                -After $cutoffDate `
                -ErrorAction SilentlyContinue |
            Select-Object -First $MaxEventsToAnalyze
        )

        if ($systemEvents.Count -eq 0) {
            Write-Log 'No System events found.' 'INFO'
            return @()
        }

        Write-Log "Total System Events: $($systemEvents.Count)" 'INFO'
        Write-Log '' 'INFO'

        $errorEvents = @(
            $systemEvents | Where-Object {
                $_.EntryType -eq 'Error'
            }
        )

        $warningEvents = @(
            $systemEvents | Where-Object {
                $_.EntryType -eq 'Warning'
            }
        )

        $infoEvents = @(
            $systemEvents | Where-Object {
                $_.EntryType -eq 'Information'
            }
        )

        Write-Log "Error Events: $($errorEvents.Count)" 'ERROR'
        Write-Log "Warning Events: $($warningEvents.Count)" 'WARNING'
        Write-Log "Information Events: $($infoEvents.Count)" 'SUCCESS'

        $Script:CriticalErrorsCount += $errorEvents.Count
        $Script:WarningsCount += $warningEvents.Count
        $Script:InfoCount += $infoEvents.Count

        Write-Log '' 'INFO'

        if ($errorEvents.Count -gt 0) {
            Write-Log 'Top Error Sources:' 'ERROR'

            $errorEvents |
                Group-Object -Property Source |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Log " - $($_.Name): $($_.Count) errors" 'ERROR'
                }
        }

        Write-Log '' 'INFO'

        if ($warningEvents.Count -gt 0) {
            Write-Log 'Top Warning Sources:' 'WARNING'

            $warningEvents |
                Group-Object -Property Source |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Log " - $($_.Name): $($_.Count) warnings" 'WARNING'
                }
        }

        Write-Log '' 'INFO'

        return $systemEvents
    }
    catch {
        Write-Log "Error analyzing System log: $($_.Exception.Message)" 'ERROR'
        return @()
    }
}

function Analyze-SecurityLog {
    Write-Log 'ANALYZING SECURITY EVENT LOG' 'INFO'
    Show-Separator

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        Write-Log "Analyzing Security events from the last $DaysToAnalyze days..." 'INFO'
        Write-Log '' 'INFO'

        $securityEvents = @(
            Get-EventLog `
                -LogName Security `
                -After $cutoffDate `
                -ErrorAction SilentlyContinue |
            Select-Object -First $MaxEventsToAnalyze
        )

        if ($securityEvents.Count -eq 0) {
            Write-Log 'No Security events found.' 'INFO'
            return @()
        }

        Write-Log "Total Security Events: $($securityEvents.Count)" 'INFO'
        Write-Log '' 'INFO'

        $errorEvents = @(
            $securityEvents | Where-Object {
                $_.EntryType -eq 'Error'
            }
        )

        $warningEvents = @(
            $securityEvents | Where-Object {
                $_.EntryType -eq 'Warning'
            }
        )

        $auditSuccess = @(
            $securityEvents | Where-Object {
                $_.EventID -eq 4624
            }
        )

        $auditFailure = @(
            $securityEvents | Where-Object {
                $_.EventID -eq 4625
            }
        )

        Write-Log "Security Errors: $($errorEvents.Count)" 'ERROR'
        Write-Log "Security Warnings: $($warningEvents.Count)" 'WARNING'
        Write-Log "Successful Logons: $($auditSuccess.Count)" 'SUCCESS'

        if ($auditFailure.Count -gt 10) {
            Write-Log "Failed Logons: $($auditFailure.Count)" 'ERROR'
        }
        else {
            Write-Log "Failed Logons: $($auditFailure.Count)" 'INFO'
        }

        $Script:SuccessAuditCount += $auditSuccess.Count

        Write-Log '' 'INFO'

        if ($auditFailure.Count -gt 10) {
            Write-Log 'HIGH NUMBER OF FAILED LOGON ATTEMPTS DETECTED.' 'ERROR'
            Write-Log 'This may indicate a security threat or password-guessing attempt.' 'ERROR'

            $failureSources = @(
                $auditFailure |
                    Group-Object -Property Source |
                    Sort-Object -Property Count -Descending
            )

            if ($failureSources.Count -gt 0) {
                Write-Log 'Failed Logon Sources:' 'ERROR'

                foreach ($source in ($failureSources | Select-Object -First 5)) {
                    Write-Log " - $($source.Name): $($source.Count) failed attempts" 'ERROR'
                }
            }
        }

        Write-Log '' 'INFO'

        return $securityEvents
    }
    catch {
        Write-Log "Error analyzing Security log: $($_.Exception.Message)" 'ERROR'
        return @()
    }
}

function Analyze-ApplicationLog {
    Write-Log 'ANALYZING APPLICATION EVENT LOG' 'INFO'
    Show-Separator

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        Write-Log "Analyzing Application events from the last $DaysToAnalyze days..." 'INFO'
        Write-Log '' 'INFO'

        $appEvents = @(
            Get-EventLog `
                -LogName Application `
                -After $cutoffDate `
                -ErrorAction SilentlyContinue |
            Select-Object -First $MaxEventsToAnalyze
        )

        if ($appEvents.Count -eq 0) {
            Write-Log 'No Application events found.' 'INFO'
            return @()
        }

        Write-Log "Total Application Events: $($appEvents.Count)" 'INFO'
        Write-Log '' 'INFO'

        $errorEvents = @(
            $appEvents | Where-Object {
                $_.EntryType -eq 'Error'
            }
        )

        $warningEvents = @(
            $appEvents | Where-Object {
                $_.EntryType -eq 'Warning'
            }
        )

        $infoEvents = @(
            $appEvents | Where-Object {
                $_.EntryType -eq 'Information'
            }
        )

        Write-Log "Application Errors: $($errorEvents.Count)" 'ERROR'
        Write-Log "Application Warnings: $($warningEvents.Count)" 'WARNING'
        Write-Log "Application Information: $($infoEvents.Count)" 'SUCCESS'

        $Script:CriticalErrorsCount += $errorEvents.Count
        $Script:WarningsCount += $warningEvents.Count
        $Script:InfoCount += $infoEvents.Count

        Write-Log '' 'INFO'

        if ($errorEvents.Count -gt 0) {
            Write-Log 'Applications with the Most Errors:' 'ERROR'

            $errorEvents |
                Group-Object -Property Source |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Log " - $($_.Name): $($_.Count) errors" 'ERROR'
                }
        }

        Write-Log '' 'INFO'

        return $appEvents
    }
    catch {
        Write-Log "Error analyzing Application log: $($_.Exception.Message)" 'ERROR'
        return @()
    }
}

function Detect-CrashEvents {
    Write-Log 'DETECTING SYSTEM CRASHES' 'INFO'
    Show-Separator

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        $crashEvents = @(
            Get-EventLog `
                -LogName System `
                -After $cutoffDate `
                -ErrorAction SilentlyContinue |
            Where-Object {
                $_.EventID -in @(41, 1001, 6008)
            }
        )

        if ($crashEvents.Count -eq 0) {
            Write-Log 'No system crashes detected.' 'SUCCESS'
            return
        }

        Write-Log "SYSTEM CRASHES DETECTED: $($crashEvents.Count)" 'ERROR'
        Write-Log '' 'INFO'

        foreach ($crash in ($crashEvents | Select-Object -First 10)) {
            $message = [string]$crash.Message

            if ($message.Length -gt 100) {
                $message = $message.Substring(0, 100)
            }

            Write-Log "Crash Event ID: $($crash.EventID)" 'ERROR'
            Write-Log "Time: $($crash.TimeGenerated)" 'INFO'
            Write-Log "Source: $($crash.Source)" 'INFO'
            Write-Log "Message: $message" 'INFO'
            Write-Log '' 'INFO'
        }
    }
    catch {
        Write-Log "Error detecting crashes: $($_.Exception.Message)" 'ERROR'
    }
}

function Detect-ServiceFailures {
    Write-Log 'DETECTING SERVICE FAILURES' 'INFO'
    Show-Separator

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        $serviceFailures = @(
            Get-EventLog `
                -LogName System `
                -After $cutoffDate `
                -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Source -eq 'Service Control Manager' -and
                $_.EntryType -eq 'Error'
            }
        )

        if ($serviceFailures.Count -eq 0) {
            Write-Log 'No service failures detected.' 'SUCCESS'
            return
        }

        Write-Log "SERVICE FAILURES DETECTED: $($serviceFailures.Count)" 'ERROR'
        Write-Log '' 'INFO'

        $failingServices = @(
            $serviceFailures |
                Group-Object -Property Message |
                Sort-Object -Property Count -Descending
        )

        foreach ($service in ($failingServices | Select-Object -First 5)) {
            $serviceName = [string]$service.Name

            if ($serviceName.Length -gt 100) {
                $serviceName = $serviceName.Substring(0, 100)
            }

            Write-Log "Failed Service/Event: $serviceName" 'ERROR'
            Write-Log "Failures: $($service.Count)" 'ERROR'
        }

        Write-Log '' 'INFO'
    }
    catch {
        Write-Log "Error detecting service failures: $($_.Exception.Message)" 'ERROR'
    }
}

function Export-EventsToCSV {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Events,

        [Parameter(Mandatory = $true)]
        [string]$LogType
    )

    if ($null -eq $Events -or $Events.Count -eq 0) {
        Write-Log "No $LogType events to export." 'INFO'
        return
    }

    try {
        $exportRows = $Events |
            Select-Object TimeGenerated, EntryType, Source, EventID, Message

        if (Test-Path -LiteralPath $CSVExportFile) {
            $exportRows |
                Export-Csv `
                    -LiteralPath $CSVExportFile `
                    -Append `
                    -NoTypeInformation `
                    -Encoding UTF8
        }
        else {
            $exportRows |
                Export-Csv `
                    -LiteralPath $CSVExportFile `
                    -NoTypeInformation `
                    -Encoding UTF8
        }

        Write-Log "$LogType events exported to: $CSVExportFile" 'SUCCESS'
    }
    catch {
        Write-Log "Could not export $LogType events to CSV: $($_.Exception.Message)" 'WARNING'
    }
}

function Generate-HTMLReport {
    Write-Log 'Generating HTML report...' 'INFO'

    try {
        $generatedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Event Log Analysis Report</title>
<style>
body {
    font-family: Arial, sans-serif;
    background-color: #f5f5f5;
    margin: 20px;
    color: #222;
}

.header {
    background-color: #0078d4;
    color: white;
    padding: 20px;
    border-radius: 5px;
    margin-bottom: 20px;
}

.section {
    background-color: white;
    padding: 15px;
    margin-bottom: 15px;
    border-radius: 5px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.section h2 {
    color: #0078d4;
    border-bottom: 2px solid #0078d4;
    padding-bottom: 10px;
}

.stat {
    display: inline-block;
    background-color: #f0f0f0;
    padding: 15px 25px;
    margin: 10px 10px 10px 0;
    border-radius: 5px;
    font-weight: bold;
}

.error {
    color: #dc3545;
}

.warning {
    color: #d39e00;
}

.success {
    color: #28a745;
}

.info {
    color: #17a2b8;
}

.footer {
    text-align: center;
    color: #999;
    margin-top: 30px;
    font-size: 12px;
}
</style>
</head>
<body>

<div class="header">
    <h1>Event Log Analysis Report</h1>
    <p>Generated: $generatedDate</p>
    <p>Analysis Period: Last $DaysToAnalyze days</p>
</div>

<div class="section">
    <h2>Summary Statistics</h2>
    <div class="stat error">
        Errors: $($Script:CriticalErrorsCount)
    </div>
    <div class="stat warning">
        Warnings: $($Script:WarningsCount)
    </div>
    <div class="stat info">
        Information: $($Script:InfoCount)
    </div>
    <div class="stat success">
        Successful Audits: $($Script:SuccessAuditCount)
    </div>
</div>

<div class="section">
    <h2>Key Findings</h2>
    <ul>
        <li>Total errors: $($Script:CriticalErrorsCount)</li>
        <li>Total warnings: $($Script:WarningsCount)</li>
        <li>Total information events: $($Script:InfoCount)</li>
        <li>Successful logons: $($Script:SuccessAuditCount)</li>
        <li>Analysis period: $DaysToAnalyze days</li>
        <li>Maximum events per log: $MaxEventsToAnalyze</li>
    </ul>
</div>

<div class="section">
    <h2>Recommendations</h2>
    <ul>
        <li>Review error events for repeated patterns.</li>
        <li>Address critical failures immediately.</li>
        <li>Check application compatibility issues.</li>
        <li>Monitor failed security events.</li>
        <li>Update problematic drivers and software.</li>
        <li>Maintain regular backups.</li>
    </ul>
</div>

<div class="footer">
    <p>Event Log Analysis Report</p>
</div>

</body>
</html>
"@

        Set-Content `
            -LiteralPath $ReportFile `
            -Value $htmlContent `
            -Encoding UTF8

        Write-Log "HTML report saved to: $ReportFile" 'SUCCESS'
    }
    catch {
        Write-Log "Could not generate HTML report: $($_.Exception.Message)" 'WARNING'
    }
}

function Show-AnalysisReport {
    $totalEvents =
        $Script:CriticalErrorsCount +
        $Script:WarningsCount +
        $Script:InfoCount +
        $Script:SuccessAuditCount

    Write-Log '' 'INFO'
    Show-Separator
    Write-Log 'EVENT LOG ANALYSIS SUMMARY REPORT' 'INFO'
    Show-Separator

    Write-Log "Analysis Period: Last $DaysToAnalyze days" 'INFO'
    Write-Log '' 'INFO'

    Write-Log 'TOTAL EVENTS BY TYPE:' 'INFO'
    Write-Log "Critical Errors: $($Script:CriticalErrorsCount)" 'ERROR'
    Write-Log "Warnings: $($Script:WarningsCount)" 'WARNING'
    Write-Log "Information: $($Script:InfoCount)" 'INFO'
    Write-Log "Successful Audits: $($Script:SuccessAuditCount)" 'SUCCESS'
    Write-Log "Total Events Analyzed: $totalEvents" 'INFO'

    Write-Log '' 'INFO'
    Write-Log 'HEALTH ASSESSMENT:' 'INFO'

    if ($Script:CriticalErrorsCount -gt 50) {
        Write-Log 'CRITICAL: High number of errors detected.' 'ERROR'
    }
    elseif ($Script:CriticalErrorsCount -gt 20) {
        Write-Log 'WARNING: Significant error activity detected.' 'WARNING'
    }
    else {
        Write-Log 'OK: Error levels are acceptable.' 'SUCCESS'
    }

    Write-Log '' 'INFO'
    Write-Log 'FILES GENERATED:' 'INFO'
    Write-Log "Text Log: $LogFile" 'SUCCESS'
    Write-Log "HTML Report: $ReportFile" 'SUCCESS'
    Write-Log "CSV Export: $CSVExportFile" 'SUCCESS'
}

function Main {
    Write-Log '================================================================' 'INFO'
    Write-Log 'EVENT LOG ANALYZER SCRIPT' 'INFO'
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
    Write-Log "Output Directory: $LogPath" 'INFO'
    Write-Log "Log File: $LogFile" 'INFO'
    Show-Separator

    Write-Log 'PHASE 1: SYSTEM LOG ANALYSIS' 'INFO'
    Show-Separator
    $systemEvents = Analyze-SystemLog

    Write-Log 'PHASE 2: APPLICATION LOG ANALYSIS' 'INFO'
    Show-Separator
    $appEvents = Analyze-ApplicationLog

    Write-Log 'PHASE 3: SECURITY LOG ANALYSIS' 'INFO'
    Show-Separator
    $securityEvents = Analyze-SecurityLog

    Write-Log 'PHASE 4: SYSTEM CRASH DETECTION' 'INFO'
    Show-Separator
    Detect-CrashEvents

    Write-Log 'PHASE 5: SERVICE FAILURE DETECTION' 'INFO'
    Show-Separator
    Detect-ServiceFailures

    Write-Log 'PHASE 6: EXPORT ANALYSIS DATA' 'INFO'
    Show-Separator

    if ($systemEvents.Count -gt 0) {
        Export-EventsToCSV -Events $systemEvents -LogType 'System'
    }

    if ($appEvents.Count -gt 0) {
        Export-EventsToCSV -Events $appEvents -LogType 'Application'
    }

    if ($securityEvents.Count -gt 0) {
        Export-EventsToCSV -Events $securityEvents -LogType 'Security'
    }

    Write-Log 'PHASE 7: GENERATE REPORTS' 'INFO'
    Show-Separator
    Generate-HTMLReport

    Show-AnalysisReport

    Write-Log '' 'INFO'
    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
    Write-Log '================================================================' 'INFO'
}

# ========== RUN SCRIPT ==========

Main
