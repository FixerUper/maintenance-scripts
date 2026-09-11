<#
.SYNOPSIS
    Event Log Analyzer Script
    Analyzes Windows Event Logs for errors, warnings, and security issues

.DESCRIPTION
    This script performs comprehensive event log analysis including:
    - Parse Windows Event Logs
    - Identify critical errors and warnings
    - Track system crashes and failures
    - Monitor application errors
    - Detect suspicious security events
    - Analyze failed logon attempts
    - Generate event summary report
    - Export findings to multiple formats
    - Identify top error sources
    - Trend analysis over time
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Log file: $env:USERPROFILE\Documents\EventLogAnalysis_YYYYMMDD_HHmmss.log

.AUTHOR
    Event Log Analyzer Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "EventLogAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$ReportFile = Join-Path -Path $LogPath -ChildPath "EventLogReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
$CSVExportFile = Join-Path -Path $LogPath -ChildPath "EventLogExport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

# Analysis parameters
$DaysToAnalyze = 7
$MaxEventsToAnalyze = 10000
$Script:CriticalErrorsCount = 0
$Script:WarningsCount = 0
$Script:InfoCount = 0
$Script:SuccessAuditCount = 0

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

function Analyze-SystemLog {
    <#
    .SYNOPSIS
        Analyze System Event Log
    #>
    Write-Log "ANALYZING SYSTEM EVENT LOG" "INFO"
    Show-Separator
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)
        Write-Log "Analyzing events from the last $DaysToAnalyze days..." "INFO"
        Write-Log "" "INFO"
        
        # Get all system events
        $systemEvents = Get-EventLog -LogName System -After $cutoffDate -ErrorAction SilentlyContinue | 
                        Select-Object -First $MaxEventsToAnalyze
        
        if ($null -eq $systemEvents) {
            Write-Log "No system events found" "INFO"
            return $null
        }
        
        Write-Log "Total System Events: $($systemEvents.Count)" "INFO"
        Write-Log "" "INFO"
        
        # Analyze by type
        $errorEvents = $systemEvents | Where-Object { $_.EntryType -eq "Error" }
        $warningEvents = $systemEvents | Where-Object { $_.EntryType -eq "Warning" }
        $infoEvents = $systemEvents | Where-Object { $_.EntryType -eq "Information" }
        
        Write-Log "Error Events: $($errorEvents.Count)" "ERROR"
        Write-Log "Warning Events: $($warningEvents.Count)" "WARNING"
        Write-Log "Information Events: $($infoEvents.Count)" "SUCCESS"
        
        $Script:CriticalErrorsCount += $errorEvents.Count
        $Script:WarningsCount += $warningEvents.Count
        $Script:InfoCount += $infoEvents.Count
        
        Write-Log "" "INFO"
        
        # Top error sources
        if ($errorEvents.Count -gt 0) {
            Write-Log "Top Error Sources:" "ERROR"
            $errorEvents | Group-Object -Property Source | Sort-Object -Property Count -Descending | 
            Select-Object -First 5 | ForEach-Object {
                Write-Log "  • $($_.Name): $($_.Count) errors" "ERROR"
            }
        }
        
        Write-Log "" "INFO"
        
        # Top warning sources
        if ($warningEvents.Count -gt 0) {
            Write-Log "Top Warning Sources:" "WARNING"
            $warningEvents | Group-Object -Property Source | Sort-Object -Property Count -Descending | 
            Select-Object -First 5 | ForEach-Object {
                Write-Log "  • $($_.Name): $($_.Count) warnings" "WARNING"
            }
        }
        
        Write-Log "" "INFO"
        return $systemEvents
    }
    catch {
        Write-Log "Error analyzing System Log: $_" "ERROR"
        return $null
    }
}

function Analyze-SecurityLog {
    <#
    .SYNOPSIS
        Analyze Security Event Log
    #>
    Write-Log "ANALYZING SECURITY EVENT LOG" "INFO"
    Show-Separator
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)
        Write-Log "Analyzing security events from the last $DaysToAnalyze days..." "INFO"
        Write-Log "" "INFO"
        
        # Get security events
        $securityEvents = Get-EventLog -LogName Security -After $cutoffDate -ErrorAction SilentlyContinue | 
                          Select-Object -First $MaxEventsToAnalyze
        
        if ($null -eq $securityEvents) {
            Write-Log "No security events found" "INFO"
            return $null
        }
        
        Write-Log "Total Security Events: $($securityEvents.Count)" "INFO"
        Write-Log "" "INFO"
        
        # Analyze by type
        $errorEvents = $securityEvents | Where-Object { $_.EntryType -eq "Error" }
        $warningEvents = $securityEvents | Where-Object { $_.EntryType -eq "Warning" }
        $auditSuccess = $securityEvents | Where-Object { $_.EventID -match "4624" }  # Successful logon
        $auditFailure = $securityEvents | Where-Object { $_.EventID -match "4625" }  # Failed logon
        
        Write-Log "Security Errors: $($errorEvents.Count)" "ERROR"
        Write-Log "Security Warnings: $($warningEvents.Count)" "WARNING"
        Write-Log "Successful Logons: $($auditSuccess.Count)" "SUCCESS"
        Write-Log "Failed Logons: $($auditFailure.Count)" $(if ($auditFailure.Count -gt 10) { "ERROR" } else { "INFO" })
        
        $Script:SuccessAuditCount += $auditSuccess.Count
        
        Write-Log "" "INFO"
        
        # Alert on high failed logon attempts
        if ($auditFailure.Count -gt 10) {
            Write-Log "⚠ HIGH NUMBER OF FAILED LOGON ATTEMPTS" "ERROR"
            Write-Log "This may indicate a security threat or password guessing attempt" "ERROR"
            
            # Identify sources of failed logons
            $failureSources = $auditFailure | Group-Object -Property Source | Sort-Object -Property Count -Descending
            Write-Log "Failed Logon Sources:" "ERROR"
            foreach ($source in $failureSources | Select-Object -First 5) {
                Write-Log "  • $($source.Name): $($source.Count) failed attempts" "ERROR"
            }
        }
        
        Write-Log "" "INFO"
        return $securityEvents
    }
    catch {
        Write-Log "Error analyzing Security Log: $_" "ERROR"
        return $null
    }
}

function Analyze-ApplicationLog {
    <#
    .SYNOPSIS
        Analyze Application Event Log
    #>
    Write-Log "ANALYZING APPLICATION EVENT LOG" "INFO"
    Show-Separator
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)
        Write-Log "Analyzing application events from the last $DaysToAnalyze days..." "INFO"
        Write-Log "" "INFO"
        
        # Get application events
        $appEvents = Get-EventLog -LogName Application -After $cutoffDate -ErrorAction SilentlyContinue | 
                     Select-Object -First $MaxEventsToAnalyze
        
        if ($null -eq $appEvents) {
            Write-Log "No application events found" "INFO"
            return $null
        }
        
        Write-Log "Total Application Events: $($appEvents.Count)" "INFO"
        Write-Log "" "INFO"
        
        # Analyze by type
        $errorEvents = $appEvents | Where-Object { $_.EntryType -eq "Error" }
        $warningEvents = $appEvents | Where-Object { $_.EntryType -eq "Warning" }
        $infoEvents = $appEvents | Where-Object { $_.EntryType -eq "Information" }
        
        Write-Log "Application Errors: $($errorEvents.Count)" "ERROR"
        Write-Log "Application Warnings: $($warningEvents.Count)" "WARNING"
        Write-Log "Application Information: $($infoEvents.Count)" "SUCCESS"
        
        $Script:CriticalErrorsCount += $errorEvents.Count
        $Script:WarningsCount += $warningEvents.Count
        $Script:InfoCount += $infoEvents.Count
        
        Write-Log "" "INFO"
        
        # Top problematic applications
        if ($errorEvents.Count -gt 0) {
            Write-Log "Applications with Most Errors:" "ERROR"
            $errorEvents | Group-Object -Property Source | Sort-Object -Property Count -Descending | 
            Select-Object -First 5 | ForEach-Object {
                Write-Log "  • $($_.Name): $($_.Count) errors" "ERROR"
            }
        }
        
        Write-Log "" "INFO"
        return $appEvents
    }
    catch {
        Write-Log "Error analyzing Application Log: $_" "ERROR"
        return $null
    }
}

function Detect-CrashEvents {
    <#
    .SYNOPSIS
        Detect and report system crash events
    #>
    Write-Log "DETECTING SYSTEM CRASHES" "INFO"
    Show-Separator
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)
        
        # Look for critical events that indicate crashes
        $crashEvents = Get-EventLog -LogName System -After $cutoffDate -ErrorAction SilentlyContinue | 
                       Where-Object { $_.EventID -eq 41 -or $_.EventID -eq 1001 -or $_.EventID -eq 6008 }
        
        if ($null -eq $crashEvents -or $crashEvents.Count -eq 0) {
            Write-Log "✓ No system crashes detected" "SUCCESS"
            return
        }
        
        Write-Log "⚠ SYSTEM CRASHES DETECTED: $($crashEvents.Count)" "ERROR"
        Write-Log "" "INFO"
        
        foreach ($crash in $crashEvents | Select-Object -First 10) {
            Write-Log "Crash Event ID: $($crash.EventID)" "ERROR"
            Write-Log "  Time: $($crash.TimeGenerated)" "INFO"
            Write-Log "  Source: $($crash.Source)" "INFO"
            Write-Log "  Message: $($crash.Message.Substring(0, [Math]::Min(100, $crash.Message.Length)))" "INFO"
            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log "Error detecting crashes: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Detect-ServiceFailures {
    <#
    .SYNOPSIS
        Detect Windows service failures
    #>
    Write-Log "DETECTING SERVICE FAILURES" "INFO"
    Show-Separator
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)
        
        # Look for service failure events
        $serviceFailures = Get-EventLog -LogName System -After $cutoffDate -ErrorAction SilentlyContinue | 
                          Where-Object { $_.Source -eq "Service Control Manager" -and $_.EntryType -eq "Error" }
        
        if ($null -eq $serviceFailures -or $serviceFailures.Count -eq 0) {
            Write-Log "✓ No service failures detected" "SUCCESS"
            Write-Log "" "INFO"
            return
        }
        
        Write-Log "⚠ SERVICE FAILURES DETECTED: $($serviceFailures.Count)" "ERROR"
        Write-Log "" "INFO"
        
        # Identify failing services
        $failingServices = $serviceFailures | Group-Object -Property Message | Sort-Object -Property Count -Descending
        
        foreach ($service in $failingServices | Select-Object -First 5) {
            Write-Log "Failed Service: $($service.Name.Substring(0, [Math]::Min(80, $service.Name.Length)))" "ERROR"
            Write-Log "  Failures: $($service.Count)" "ERROR"
        }
        
        Write-Log "" "INFO"
    }
    catch {
        Write-Log "Error detecting service failures: $_" "ERROR"
        Write-Log "" "INFO"
    }
}

function Export-EventsToCSV {
    <#
    .SYNOPSIS
        Export events to CSV for external analysis
    #>
    param(
        [object[]]$Events,
        [string]$LogType
    )
    
    Write-Log "Exporting $LogType events to CSV..." "INFO"
    
    try {
        $events | Select-Object TimeGenerated, EntryType, Source, EventID, Message | 
        Export-Csv -Path $CSVExportFile -Append -NoTypeInformation -ErrorAction SilentlyContinue
        
        Write-Log "✓ Events exported to: $CSVExportFile" "SUCCESS"
    }
    catch {
        Write-Log "Could not export to CSV: $_" "WARNING"
    }
}

function Generate-HTMLReport {
    <#
    .SYNOPSIS
        Generate HTML summary report
    #>
    Write-Log "Generating HTML report..." "INFO"
    
    try {
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Event Log Analysis Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #f5f5f5;
            margin: 20px;
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
        .error { color: #dc3545; }
        .warning { color: #ffc107; }
        .success { color: #28a745; }
        .info { color: #17a2b8; }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 10px;
            text-align: left;
        }
        th {
            background-color: #f0f0f0;
            font-weight: bold;
        }
        tr:hover {
            background-color: #f9f9f9;
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
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p>Analysis Period: Last $DaysToAnalyze days</p>
    </div>
    
    <div class="section">
        <h2>Summary Statistics</h2>
        <div class="stat error">Errors: $($Script:CriticalErrorsCount)</div>
        <div class="stat warning">Warnings: $($Script:WarningsCount)</div>
        <div class="stat info">Information: $($Script:InfoCount)</div>
        <div class="stat success">Success Audits: $($Script:SuccessAuditCount)</div>
    </div>
    
    <div class="section">
        <h2>Key Findings</h2>
        <ul>
            <li>Total Critical Events: $($Script:CriticalErrorsCount)</li>
            <li>Total Warnings: $($Script:WarningsCount)</li>
            <li>Analysis Period: $DaysToAnalyze days</li>
            <li>Max Events Analyzed: $MaxEventsToAnalyze</li>
        </ul>
    </div>
    
    <div class="section">
        <h2>Recommendations</h2>
        <ul>
            <li>Review error events for patterns and root causes</li>
            <li>Address critical failures immediately</li>
            <li>Check application compatibility issues</li>
            <li>Monitor security events for threats</li>
            <li>Update problematic drivers and software</li>
            <li>Maintain regular backups</li>
        </ul>
    </div>
    
    <div class="footer">
        <p>Event Log Analysis Report | Generated by PowerShell Maintenance Suite</p>
    </div>
</body>
</html>
"@
        
        Set-Content -Path $ReportFile -Value $htmlContent
        Write-Log "✓ HTML report saved: $ReportFile" "SUCCESS"
    }
    catch {
        Write-Log "Could not generate HTML report: $_" "WARNING"
    }
}

function Show-AnalysisReport {
    <#
    .SYNOPSIS
        Display analysis summary report
    #>
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "EVENT LOG ANALYSIS SUMMARY REPORT" "INFO"
    Show-Separator
    
    Write-Log "Analysis Period: Last $DaysToAnalyze days" "INFO"
    Write-Log "" "INFO"
    
    Write-Log "TOTAL EVENTS BY TYPE:" "INFO"
    Write-Log "Critical Errors: $($Script:CriticalErrorsCount)" "ERROR"
    Write-Log "Warnings: $($Script:WarningsCount)" "WARNING"
    Write-Log "Information: $($Script:InfoCount)" "INFO"
    Write-Log "Success Audits: $($Script:SuccessAuditCount)" "SUCCESS"
    
    Write-Log "" "INFO"
    
    $totalEvents = $Script:CriticalErrorsCount + $Script:WarningsCount + $Script:InfoCount + $Script:SuccessAuditCount
    Write-Log "Total Events Analyzed: $totalEvents" "INFO"
    
    Write-Log "" "INFO"
    Write-Log "HEALTH ASSESSMENT:" "INFO"
    
    if ($Script:CriticalErrorsCount -gt 50) {
        Write-Log "✗ CRITICAL: High number of errors detected" "ERROR"
    } elseif ($Script:CriticalErrorsCount -gt 20) {
        Write-Log "⚠ WARNING: Significant error activity detected" "WARNING"
    } else {
        Write-Log "✓ OK: Error levels are acceptable" "SUCCESS"
    }
    
    Write-Log "" "INFO"
    Write-Log "FILES GENERATED:" "INFO"
    Write-Log "  • Text Log: $LogFile" "SUCCESS"
    Write-Log "  • HTML Report: $ReportFile" "SUCCESS"
    Write-Log "  • CSV Export: $CSVExportFile" "SUCCESS"
    
    Write-Log "" "INFO"
    Write-Log "NEXT STEPS:" "INFO"
    Write-Log "  1. Review error events for patterns" "INFO"
    Write-Log "  2. Check application compatibility" "INFO"
    Write-Log "  3. Update drivers and software" "INFO"
    Write-Log "  4. Monitor security logs regularly" "INFO"
    
    Show-Separator
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "EVENT LOG ANALYZER SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: SYSTEM LOG ANALYSIS =====
    Write-Log "PHASE 1: SYSTEM LOG ANALYSIS" "INFO"
    Show-Separator
    $systemEvents = Analyze-SystemLog
    Show-Separator
    
    # ===== PHASE 2: APPLICATION LOG ANALYSIS =====
    Write-Log "PHASE 2: APPLICATION LOG ANALYSIS" "INFO"
    Show-Separator
    $appEvents = Analyze-ApplicationLog
    Show-Separator
    
    # ===== PHASE 3: SECURITY LOG ANALYSIS =====
    Write-Log "PHASE 3: SECURITY LOG ANALYSIS" "INFO"
    Show-Separator
    $securityEvents = Analyze-SecurityLog
    Show-Separator
    
    # ===== PHASE 4: CRASH DETECTION =====
    Write-Log "PHASE 4: SYSTEM CRASH DETECTION" "INFO"
    Show-Separator
    Detect-CrashEvents
    Show-Separator
    
    # ===== PHASE 5: SERVICE FAILURE DETECTION =====
    Write-Log "PHASE 5: SERVICE FAILURE DETECTION" "INFO"
    Show-Separator
    Detect-ServiceFailures
    Show-Separator
    
    # ===== PHASE 6: EXPORT DATA =====
    Write-Log "PHASE 6: EXPORT ANALYSIS DATA" "INFO"
    Show-Separator
    
    if ($null -ne $systemEvents) {
        Export-EventsToCSV -Events $systemEvents -LogType "System"
    }
    
    if ($null -ne $appEvents) {
        Export-EventsToCSV -Events $appEvents -LogType "Application"
    }
    
    if ($null -ne $securityEvents) {
        Export-EventsToCSV -Events $securityEvents -LogType "Security"
    }
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== PHASE 7: GENERATE REPORTS =====
    Write-Log "PHASE 7: GENERATE REPORTS" "INFO"
    Show-Separator
    Generate-HTMLReport
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== COMPLETION SUMMARY =====
    Show-AnalysisReport
    
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
