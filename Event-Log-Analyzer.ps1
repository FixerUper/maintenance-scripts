<#
.SYNOPSIS
    Windows Event Log Analyzer

.DESCRIPTION
    Analyzes the Windows System, Application, and Security event logs for:

    - Errors and warnings
    - Failed and successful logons
    - System crashes and unexpected shutdowns
    - Windows service failures
    - Common error sources

    Results are written to C:\temp by default.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7+
    Requires Administrator privileges
#>

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION
# ============================================================================

$LogPath = 'C:\temp'
$DaysToAnalyze = 7
$MaxEventsToAnalyze = 10000
$FailedLogonWarningThreshold = 10

$TimeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$LogFile = Join-Path `
    -Path $LogPath `
    -ChildPath "EventLogAnalysis_$TimeStamp.log"

$ReportFile = Join-Path `
    -Path $LogPath `
    -ChildPath "EventLogReport_$TimeStamp.html"

$CSVExportFile = Join-Path `
    -Path $LogPath `
    -ChildPath "EventLogExport_$TimeStamp.csv"

# ============================================================================
# GLOBAL STATISTICS
# ============================================================================

$Script:CriticalErrorsCount = 0
$Script:WarningsCount = 0
$Script:InfoCount = 0
$Script:SuccessLogonCount = 0
$Script:AnalysisErrors = 0
$Script:EventsRead = 0
$Script:CrashCount = 0
$Script:ServiceFailureCount = 0

# Ensure output directory exists
if (-not (Test-Path -LiteralPath $LogPath)) {
    New-Item `
        -ItemType Directory `
        -Path $LogPath `
        -Force |
        Out-Null
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Message = '',

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $TimestampText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Keep blank log entries as clean separator lines
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $LogMessage = "[$TimestampText] [$Level]"
    }
    else {
        $LogMessage = "[$TimestampText] [$Level] $Message"
    }

    switch ($Level) {
        'INFO' {
            Write-Host $LogMessage -ForegroundColor White
        }

        'WARNING' {
            Write-Host $LogMessage -ForegroundColor Yellow
        }

        'ERROR' {
            Write-Host $LogMessage -ForegroundColor Red
        }

        'SUCCESS' {
            Write-Host $LogMessage -ForegroundColor Green
        }
    }

    try {
        Add-Content `
            -LiteralPath $LogFile `
            -Value $LogMessage `
            -Encoding UTF8 `
            -ErrorAction Stop
    }
    catch {
        Write-Host "Unable to write to log file: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}

function Write-LogBlank {
    Write-Log -Message '' -Level 'INFO'
}

function Show-Separator {
    Write-Log '================================================================' 'INFO'
}

# ============================================================================
# EVENT HELPERS
# ============================================================================

function Get-RecentEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogName,

        [Parameter(Mandatory = $true)]
        [datetime]$Since,

        [Parameter(Mandatory = $true)]
        [int]$Maximum
    )

    try {
        $Events = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = $LogName
                StartTime = $Since
            } `
            -MaxEvents $Maximum `
            -ErrorAction Stop
        )

        return $Events
    }
    catch {
        $Script:AnalysisErrors++

        Write-Log `
            "Unable to read the $LogName event log: $($_.Exception.Message)" `
            'ERROR'

        return @()
    }
}

function Get-EventMessage {
    param(
        [Parameter(Mandatory = $false)]
        $Event
    )

    if ($null -eq $Event) {
        return '[No event message available]'
    }

    try {
        $Message = [string]$Event.Message
    }
    catch {
        $Message = ''
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return '[No event message available]'
    }

    return $Message
}

function Get-EventProvider {
    param(
        [Parameter(Mandatory = $false)]
        $Event
    )

    if ($null -eq $Event) {
        return 'Unknown'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Event.ProviderName)) {
        return [string]$Event.ProviderName
    }

    return 'Unknown'
}

function Get-EventLevel {
    param(
        [Parameter(Mandatory = $false)]
        $Event
    )

    if ($null -eq $Event) {
        return 'Unknown'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Event.LevelDisplayName)) {
        return [string]$Event.LevelDisplayName
    }

    return 'Unknown'
}

function Get-EventIdValue {
    param(
        [Parameter(Mandatory = $false)]
        $Event
    )

    if ($null -eq $Event) {
        return 0
    }

    return [int]$Event.Id
}

function Get-EventTime {
    param(
        [Parameter(Mandatory = $false)]
        $Event
    )

    if ($null -eq $Event) {
        return ''
    }

    if ($null -eq $Event.TimeCreated) {
        return ''
    }

    return $Event.TimeCreated
}

function Get-ShortText {
    param(
        [AllowEmptyString()]
        [string]$Text = '',

        [int]$MaximumLength = 120
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return '[No information available]'
    }

    if ($Text.Length -gt $MaximumLength) {
        return $Text.Substring(0, $MaximumLength) + '...'
    }

    return $Text
}

# ============================================================================
# SYSTEM LOG ANALYSIS
# ============================================================================

function Analyze-SystemLog {
    Write-Log 'ANALYZING SYSTEM EVENT LOG' 'INFO'
    Show-Separator

    try {
        $CutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        Write-Log `
            "Analyzing System events from the last $DaysToAnalyze days..." `
            'INFO'

        Write-LogBlank

        $SystemEvents = @(
            Get-RecentEvents `
                -LogName 'System' `
                -Since $CutoffDate `
                -Maximum $MaxEventsToAnalyze
        )

        if ($SystemEvents.Count -eq 0) {
            Write-Log 'No System events found or the log could not be read.' 'WARNING'
            return @()
        }

        $Script:EventsRead += $SystemEvents.Count

        Write-Log `
            "Total System Events: $($SystemEvents.Count)" `
            'INFO'

        Write-LogBlank

        $ErrorEvents = @(
            $SystemEvents | Where-Object {
                (Get-EventLevel $_) -in @('Error', 'Critical')
            }
        )

        $WarningEvents = @(
            $SystemEvents | Where-Object {
                (Get-EventLevel $_) -eq 'Warning'
            }
        )

        $InfoEvents = @(
            $SystemEvents | Where-Object {
                (Get-EventLevel $_) -in @('Information', 'Verbose')
            }
        )

        Write-Log "System Errors: $($ErrorEvents.Count)" 'ERROR'
        Write-Log "System Warnings: $($WarningEvents.Count)" 'WARNING'
        Write-Log "System Information: $($InfoEvents.Count)" 'INFO'

        $Script:CriticalErrorsCount += $ErrorEvents.Count
        $Script:WarningsCount += $WarningEvents.Count
        $Script:InfoCount += $InfoEvents.Count

        Write-LogBlank

        if ($ErrorEvents.Count -gt 0) {
            Write-Log 'Top System Error Sources:' 'ERROR'

            $ErrorEvents |
                Group-Object -Property ProviderName |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Log `
                        " - $($_.Name): $($_.Count) errors" `
                        'ERROR'
                }

            Write-LogBlank
        }

        if ($WarningEvents.Count -gt 0) {
            Write-Log 'Top System Warning Sources:' 'WARNING'

            $WarningEvents |
                Group-Object -Property ProviderName |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Log `
                        " - $($_.Name): $($_.Count) warnings" `
                        'WARNING'
                }

            Write-LogBlank
        }

        return $SystemEvents
    }
    catch {
        $Script:AnalysisErrors++

        Write-Log `
            "Error analyzing System log: $($_.Exception.Message)" `
            'ERROR'

        return @()
    }
}

# ============================================================================
# APPLICATION LOG ANALYSIS
# ============================================================================

function Analyze-ApplicationLog {
    Write-Log 'ANALYZING APPLICATION EVENT LOG' 'INFO'
    Show-Separator

    try {
        $CutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        Write-Log `
            "Analyzing Application events from the last $DaysToAnalyze days..." `
            'INFO'

        Write-LogBlank

        $ApplicationEvents = @(
            Get-RecentEvents `
                -LogName 'Application' `
                -Since $CutoffDate `
                -Maximum $MaxEventsToAnalyze
        )

        if ($ApplicationEvents.Count -eq 0) {
            Write-Log `
                'No Application events found or the log could not be read.' `
                'WARNING'

            return @()
        }

        $Script:EventsRead += $ApplicationEvents.Count

        Write-Log `
            "Total Application Events: $($ApplicationEvents.Count)" `
            'INFO'

        Write-LogBlank

        $ErrorEvents = @(
            $ApplicationEvents | Where-Object {
                (Get-EventLevel $_) -in @('Error', 'Critical')
            }
        )

        $WarningEvents = @(
            $ApplicationEvents | Where-Object {
                (Get-EventLevel $_) -eq 'Warning'
            }
        )

        $InfoEvents = @(
            $ApplicationEvents | Where-Object {
                (Get-EventLevel $_) -in @('Information', 'Verbose')
            }
        )

        Write-Log "Application Errors: $($ErrorEvents.Count)" 'ERROR'
        Write-Log "Application Warnings: $($WarningEvents.Count)" 'WARNING'
        Write-Log "Application Information: $($InfoEvents.Count)" 'INFO'

        $Script:CriticalErrorsCount += $ErrorEvents.Count
        $Script:WarningsCount += $WarningEvents.Count
        $Script:InfoCount += $InfoEvents.Count

        Write-LogBlank

        if ($ErrorEvents.Count -gt 0) {
            Write-Log 'Applications with the Most Errors:' 'ERROR'

            $ErrorEvents |
                Group-Object -Property ProviderName |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Log `
                        " - $($_.Name): $($_.Count) errors" `
                        'ERROR'
                }

            Write-LogBlank
        }

        if ($WarningEvents.Count -gt 0) {
            Write-Log 'Applications with the Most Warnings:' 'WARNING'

            $WarningEvents |
                Group-Object -Property ProviderName |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Log `
                        " - $($_.Name): $($_.Count) warnings" `
                        'WARNING'
                }

            Write-LogBlank
        }

        return $ApplicationEvents
    }
    catch {
        $Script:AnalysisErrors++

        Write-Log `
            "Error analyzing Application log: $($_.Exception.Message)" `
            'ERROR'

        return @()
    }
}

# ============================================================================
# SECURITY LOG ANALYSIS
# ============================================================================

function Analyze-SecurityLog {
    Write-Log 'ANALYZING SECURITY EVENT LOG' 'INFO'
    Show-Separator

    try {
        $CutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        Write-Log `
            "Analyzing Security events from the last $DaysToAnalyze days..." `
            'INFO'

        Write-LogBlank

        $SecurityEvents = @(
            Get-RecentEvents `
                -LogName 'Security' `
                -Since $CutoffDate `
                -Maximum $MaxEventsToAnalyze
        )

        if ($SecurityEvents.Count -eq 0) {
            Write-Log `
                'No Security events found or the log could not be read.' `
                'WARNING'

            return @()
        }

        $Script:EventsRead += $SecurityEvents.Count

        Write-Log `
            "Total Security Events: $($SecurityEvents.Count)" `
            'INFO'

        Write-LogBlank

        $SecurityErrorEvents = @(
            $SecurityEvents | Where-Object {
                (Get-EventLevel $_) -in @('Error', 'Critical')
            }
        )

        $SecurityWarningEvents = @(
            $SecurityEvents | Where-Object {
                (Get-EventLevel $_) -eq 'Warning'
            }
        )

        $SuccessfulLogons = @(
            $SecurityEvents | Where-Object {
                (Get-EventIdValue $_) -eq 4624
            }
        )

        $FailedLogons = @(
            $SecurityEvents | Where-Object {
                (Get-EventIdValue $_) -eq 4625
            }
        )

        Write-Log `
            "Security Errors: $($SecurityErrorEvents.Count)" `
            'ERROR'

        Write-Log `
            "Security Warnings: $($SecurityWarningEvents.Count)" `
            'WARNING'

        Write-Log `
            "Successful Logons: $($SuccessfulLogons.Count)" `
            'SUCCESS'

        if ($FailedLogons.Count -gt $FailedLogonWarningThreshold) {
            Write-Log `
                "Failed Logons: $($FailedLogons.Count)" `
                'WARNING'
        }
        else {
            Write-Log `
                "Failed Logons: $($FailedLogons.Count)" `
                'INFO'
        }

        $Script:SuccessLogonCount += $SuccessfulLogons.Count
        $Script:CriticalErrorsCount += $SecurityErrorEvents.Count
        $Script:WarningsCount += $SecurityWarningEvents.Count

        Write-LogBlank

        if ($FailedLogons.Count -gt $FailedLogonWarningThreshold) {
            Write-Log `
                'HIGH NUMBER OF FAILED LOGON ATTEMPTS DETECTED.' `
                'WARNING'

            Write-Log `
                'This may indicate password guessing or a misconfigured service.' `
                'WARNING'

            Write-LogBlank

            Write-Log 'Failed Logon Sources:' 'WARNING'

            $FailedLogons |
                Group-Object -Property ProviderName |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    Write-Log `
                        " - $($_.Name): $($_.Count) failed events" `
                        'WARNING'
                }

            Write-LogBlank
        }

        return $SecurityEvents
    }
    catch {
        $Script:AnalysisErrors++

        Write-Log `
            "Error analyzing Security log: $($_.Exception.Message)" `
            'ERROR'

        return @()
    }
}

# ============================================================================
# CRASH DETECTION
# ============================================================================

function Detect-CrashEvents {
    Write-Log 'DETECTING SYSTEM CRASHES' 'INFO'
    Show-Separator

    try {
        $CutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        $CrashEvents = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                StartTime = $CutoffDate
                Id        = 41, 6008
            } `
            -MaxEvents 100 `
            -ErrorAction Stop
        )

        $WerEvents = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = 'Application'
                StartTime = $CutoffDate
                Id        = 1001
            } `
            -MaxEvents 100 `
            -ErrorAction Stop
        )

        $AllCrashEvents = @(
            $CrashEvents + $WerEvents
        )

        $Script:CrashCount = $AllCrashEvents.Count

        if ($AllCrashEvents.Count -eq 0) {
            Write-Log 'No system crashes detected.' 'SUCCESS'
            return
        }

        Write-Log `
            "SYSTEM CRASH OR WER EVENTS DETECTED: $($AllCrashEvents.Count)" `
            'ERROR'

        Write-LogBlank

        foreach ($Crash in ($AllCrashEvents | Select-Object -First 10)) {
            $Message = Get-EventMessage $Crash
            $Message = Get-ShortText -Text $Message -MaximumLength 150

            Write-Log `
                "Event ID: $(Get-EventIdValue $Crash)" `
                'ERROR'

            Write-Log `
                "Time: $(Get-EventTime $Crash)" `
                'INFO'

            Write-Log `
                "Provider: $(Get-EventProvider $Crash)" `
                'INFO'

            Write-Log `
                "Message: $Message" `
                'INFO'

            Write-LogBlank
        }
    }
    catch {
        $Script:AnalysisErrors++

        Write-Log `
            "Error detecting crashes: $($_.Exception.Message)" `
            'ERROR'
    }
}

# ============================================================================
# SERVICE FAILURE DETECTION
# ============================================================================

function Detect-ServiceFailures {
    Write-Log 'DETECTING SERVICE FAILURES' 'INFO'
    Show-Separator

    try {
        $CutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

        $ServiceFailures = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                StartTime = $CutoffDate
                ProviderName = 'Service Control Manager'
                Level = 2
            } `
            -MaxEvents $MaxEventsToAnalyze `
            -ErrorAction Stop
        )

        $Script:ServiceFailureCount = $ServiceFailures.Count

        if ($ServiceFailures.Count -eq 0) {
            Write-Log 'No service failures detected.' 'SUCCESS'
            return
        }

        Write-Log `
            "SERVICE FAILURES DETECTED: $($ServiceFailures.Count)" `
            'ERROR'

        Write-LogBlank

        $ServiceFailures |
            Group-Object -Property Id |
            Sort-Object -Property Count -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                Write-Log `
                    "Event ID $($_.Name): $($_.Count) occurrences" `
                    'ERROR'
            }

        Write-LogBlank

        foreach ($Failure in ($ServiceFailures | Select-Object -First 5)) {
            $Message = Get-EventMessage $Failure
            $Message = Get-ShortText -Text $Message -MaximumLength 150

            Write-Log `
                "Service failure: $Message" `
                'ERROR'
        }

        Write-LogBlank
    }
    catch {
        $Script:AnalysisErrors++

        Write-Log `
            "Error detecting service failures: $($_.Exception.Message)" `
            'ERROR'
    }
}

# ============================================================================
# CSV EXPORT
# ============================================================================

function Export-EventsToCSV {
    [CmdletBinding()]
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
        $ExportRows = @(
            $Events | ForEach-Object {
                [pscustomobject]@{
                    LogType       = $LogType
                    TimeGenerated = Get-EventTime $_
                    Level         = Get-EventLevel $_
                    Provider      = Get-EventProvider $_
                    EventID       = Get-EventIdValue $_
                    RecordID      = $_.RecordId
                    MachineName   = $_.MachineName
                    Message       = Get-EventMessage $_
                }
            }
        )

        if (Test-Path -LiteralPath $CSVExportFile) {
            $ExportRows |
                Export-Csv `
                    -LiteralPath $CSVExportFile `
                    -Append `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -Force
        }
        else {
            $ExportRows |
                Export-Csv `
                    -LiteralPath $CSVExportFile `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -Force
        }

        Write-Log `
            "$LogType events exported to: $CSVExportFile" `
            'SUCCESS'
    }
    catch {
        Write-Log `
            "Could not export $LogType events to CSV: $($_.Exception.Message)" `
            'WARNING'
    }
}

# ============================================================================
# HTML REPORT
# ============================================================================

function ConvertTo-HtmlSafe {
    param(
        [AllowEmptyString()]
        [string]$Text = ''
    )

    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Generate-HTMLReport {
    Write-Log 'Generating HTML report...' 'INFO'

    try {
        $GeneratedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        if ($Script:AnalysisErrors -gt 0) {
            $HealthStatus = 'INCOMPLETE'
            $HealthClass = 'warning'
            $HealthMessage = "$($Script:AnalysisErrors) analysis section(s) failed."
        }
        elseif ($Script:CriticalErrorsCount -gt 50) {
            $HealthStatus = 'CRITICAL'
            $HealthClass = 'error'
            $HealthMessage = 'A high number of critical or error events was detected.'
        }
        elseif ($Script:CriticalErrorsCount -gt 20) {
            $HealthStatus = 'WARNING'
            $HealthClass = 'warning'
            $HealthMessage = 'A significant number of error events was detected.'
        }
        else {
            $HealthStatus = 'OK'
            $HealthClass = 'success'
            $HealthMessage = 'Error levels are acceptable.'
        }

        $HtmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
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
    padding: 20px;
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
    min-width: 150px;
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
    color: #b07800;
}

.success {
    color: #218838;
}

.info {
    color: #117a8b;
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
    <p>Generated: $(ConvertTo-HtmlSafe $GeneratedDate)</p>
    <p>Analysis period: Last $DaysToAnalyze days</p>
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
        Successful logons: $($Script:SuccessLogonCount)
    </div>

    <div class="stat error">
        Crash events: $($Script:CrashCount)
    </div>

    <div class="stat error">
        Service failures: $($Script:ServiceFailureCount)
    </div>
</div>

<div class="section">
    <h2>Health Assessment</h2>

    <p class="$HealthClass">
        <strong>${HealthStatus}:</strong>
        $(ConvertTo-HtmlSafe $HealthMessage)
    </p>

    <p>
        Events read: $($Script:EventsRead)
    </p>

    <p>
        Analysis errors: $($Script:AnalysisErrors)
    </p>
</div>

<div class="section">
    <h2>Key Findings</h2>

    <ul>
        <li>Total errors: $($Script:CriticalErrorsCount)</li>
        <li>Total warnings: $($Script:WarningsCount)</li>
        <li>Total information events: $($Script:InfoCount)</li>
        <li>Successful logons: $($Script:SuccessLogonCount)</li>
        <li>Crash or Windows Error Reporting events: $($Script:CrashCount)</li>
        <li>Service failures: $($Script:ServiceFailureCount)</li>
        <li>Events read: $($Script:EventsRead)</li>
        <li>Analysis period: $DaysToAnalyze days</li>
        <li>Maximum events per log: $MaxEventsToAnalyze</li>
    </ul>
</div>

<div class="section">
    <h2>Recommendations</h2>

    <ul>
        <li>Review repeated error sources and event IDs.</li>
        <li>Investigate crash and unexpected shutdown events.</li>
        <li>Review failed logons by source and time.</li>
        <li>Check applications generating repeated errors.</li>
        <li>Review failed Windows services and their dependencies.</li>
        <li>Keep Windows, drivers, and applications updated.</li>
        <li>Maintain current backups before making system changes.</li>
    </ul>
</div>

<div class="footer">
    Event Log Analysis Report
</div>

</body>
</html>
"@

        Set-Content `
            -LiteralPath $ReportFile `
            -Value $HtmlContent `
            -Encoding UTF8 `
            -Force

        Write-Log `
            "HTML report saved to: $ReportFile" `
            'SUCCESS'
    }
    catch {
        Write-Log `
            "Could not generate HTML report: $($_.Exception.Message)" `
            'WARNING'
    }
}

# ============================================================================
# SUMMARY
# ============================================================================

function Show-AnalysisReport {
    $TotalEventsAnalyzed =
        $Script:CriticalErrorsCount +
        $Script:WarningsCount +
        $Script:InfoCount

    Write-LogBlank
    Show-Separator

    Write-Log 'EVENT LOG ANALYSIS SUMMARY REPORT' 'INFO'

    Show-Separator

    Write-Log `
        "Analysis Period: Last $DaysToAnalyze days" `
        'INFO'

    Write-LogBlank

    Write-Log 'TOTAL EVENTS BY TYPE:' 'INFO'

    Write-Log `
        "Critical Errors: $($Script:CriticalErrorsCount)" `
        'ERROR'

    Write-Log `
        "Warnings: $($Script:WarningsCount)" `
        'WARNING'

    Write-Log `
        "Information: $($Script:InfoCount)" `
        'INFO'

    Write-Log `
        "Successful Logons: $($Script:SuccessLogonCount)" `
        'SUCCESS'

    Write-Log `
        "Crash Events: $($Script:CrashCount)" `
        'ERROR'

    Write-Log `
        "Service Failures: $($Script:ServiceFailureCount)" `
        'ERROR'

    Write-Log `
        "Total Events Analyzed: $TotalEventsAnalyzed" `
        'INFO'

    Write-Log `
        "Events Read: $($Script:EventsRead)" `
        'INFO'

    Write-LogBlank

    Write-Log 'HEALTH ASSESSMENT:' 'INFO'

    if ($Script:AnalysisErrors -gt 0) {
        Write-Log `
            "INCOMPLETE: $($Script:AnalysisErrors) analysis section(s) failed." `
            'ERROR'
    }
    elseif ($Script:CriticalErrorsCount -gt 50) {
        Write-Log `
            'CRITICAL: High number of errors detected.' `
            'ERROR'
    }
    elseif ($Script:CriticalErrorsCount -gt 20) {
        Write-Log `
            'WARNING: Significant error activity detected.' `
            'WARNING'
    }
    else {
        Write-Log `
            'OK: Error levels are acceptable.' `
            'SUCCESS'
    }

    Write-LogBlank

    Write-Log 'FILES GENERATED:' 'INFO'

    Write-Log `
        "Text Log: $LogFile" `
        'SUCCESS'

    Write-Log `
        "HTML Report: $ReportFile" `
        'SUCCESS'

    Write-Log `
        "CSV Export: $CSVExportFile" `
        'SUCCESS'
}

# ============================================================================
# MAIN
# ============================================================================

function Main {
    Write-Log '================================================================' 'INFO'
    Write-Log 'EVENT LOG ANALYZER SCRIPT' 'INFO'

    Write-Log `
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
        'INFO'

    Write-Log `
        "Output Directory: $LogPath" `
        'INFO'

    Write-Log `
        "Log File: $LogFile" `
        'INFO'

    Show-Separator

    Write-Log 'PHASE 1: SYSTEM LOG ANALYSIS' 'INFO'
    Show-Separator
    $SystemEvents = Analyze-SystemLog

    Write-Log 'PHASE 2: APPLICATION LOG ANALYSIS' 'INFO'
    Show-Separator
    $ApplicationEvents = Analyze-ApplicationLog

    Write-Log 'PHASE 3: SECURITY LOG ANALYSIS' 'INFO'
    Show-Separator
    $SecurityEvents = Analyze-SecurityLog

    Write-Log 'PHASE 4: SYSTEM CRASH DETECTION' 'INFO'
    Show-Separator
    Detect-CrashEvents

    Write-Log 'PHASE 5: SERVICE FAILURE DETECTION' 'INFO'
    Show-Separator
    Detect-ServiceFailures

    Write-Log 'PHASE 6: EXPORT ANALYSIS DATA' 'INFO'
    Show-Separator

    if ($SystemEvents.Count -gt 0) {
        Export-EventsToCSV `
            -Events $SystemEvents `
            -LogType 'System'
    }

    if ($ApplicationEvents.Count -gt 0) {
        Export-EventsToCSV `
            -Events $ApplicationEvents `
            -LogType 'Application'
    }

    if ($SecurityEvents.Count -gt 0) {
        Export-EventsToCSV `
            -Events $SecurityEvents `
            -LogType 'Security'
    }

    Write-Log 'PHASE 7: GENERATE REPORTS' 'INFO'
    Show-Separator

    Generate-HTMLReport
    Show-AnalysisReport

    Write-LogBlank

    Write-Log `
        "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
        'INFO'

    Write-Log '================================================================' 'INFO'
}

# ============================================================================
# RUN SCRIPT
# ============================================================================

try {
    Main
}
catch {
    Write-Log `
        "Fatal script error: $($_.Exception.Message)" `
        'ERROR'

    exit 1
}
