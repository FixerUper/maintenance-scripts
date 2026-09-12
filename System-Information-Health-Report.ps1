<#
.SYNOPSIS
    System Information and Health Report Script

.DESCRIPTION
    Collects system information and writes:
      - A text log
      - An HTML report
      - A CSV metrics history file

.OUTPUTS
    C:\temp\SystemReport_YYYYMMDD_HHmmss.txt
    C:\temp\SystemReport_YYYYMMDD_HHmmss.html
    C:\temp\SystemMetricsHistory.csv

.NOTES
    Run PowerShell as Administrator for the most complete results.
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ============================================================================
# CONFIGURATION
# ============================================================================

$LogPath = "C:\temp"

if (-not (Test-Path -LiteralPath $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

$ReportTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$TextReportFile  = Join-Path $LogPath "SystemReport_$ReportTimestamp.txt"
$HTMLReportFile  = Join-Path $LogPath "SystemReport_$ReportTimestamp.html"
$CSVHistoryFile  = Join-Path $LogPath "SystemMetricsHistory.csv"

# Use a generic list so data added inside functions persists correctly.
$ReportData = New-Object System.Collections.Generic.List[object]

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Add-ReportData {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )

    [void]$script:ReportData.Add($Data)
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"

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

    Add-Content -LiteralPath $TextReportFile -Value $LogMessage -Encoding UTF8
}

function Show-Separator {
    Write-Log "================================================================" "INFO"
}

function Convert-BytesToGB {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [long]$Bytes
    )

    if ($Bytes -le 0) {
        return 0
    }

    return [math]::Round(($Bytes / 1GB), 2)
}

function Get-FirstReportValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $Item = $script:ReportData |
        Where-Object { $_.ContainsKey($Key) } |
        Select-Object -First 1

    if ($null -eq $Item) {
        return ""
    }

    return $Item[$Key]
}

function Escape-Html {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

# ============================================================================
# INFORMATION COLLECTION FUNCTIONS
# ============================================================================

function Get-SystemInfo {
    Write-Log "SYSTEM INFORMATION" "INFO"
    Show-Separator

    try {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem
        $Computer = Get-CimInstance -ClassName Win32_ComputerSystem

        $LastBoot = $OS.LastBootUpTime
        $Uptime = (Get-Date) - $LastBoot

        Write-Log "Computer Name: $($Computer.Name)" "INFO"
        Write-Log "Domain/Workgroup: $($Computer.Domain)" "INFO"
        Write-Log "Operating System: $($OS.Caption)" "INFO"
        Write-Log "OS Version: $($OS.Version)" "INFO"
        Write-Log "OS Build: $($OS.BuildNumber)" "INFO"
        Write-Log "System Type: $($Computer.SystemType)" "INFO"
        Write-Log "Last Boot Time: $LastBoot" "INFO"
        Write-Log "System Uptime: $($Uptime.Days) days, $($Uptime.Hours) hours, $($Uptime.Minutes) minutes" "INFO"

        Add-ReportData @{
            "Computer Name" = $Computer.Name
            "OS Name"       = $OS.Caption
            "OS Version"    = $OS.Version
            "OS Build"      = $OS.BuildNumber
            "Uptime Days"   = $Uptime.Days
            "Last Boot"     = $LastBoot
        }
    }
    catch {
        Write-Log "Error retrieving system information: $($_.Exception.Message)" "ERROR"
    }

    Write-Log "" "INFO"
}

function Get-ProcessorInfo {
    Write-Log "PROCESSOR INFORMATION" "INFO"
    Show-Separator

    try {
        $CPUs = @(Get-CimInstance -ClassName Win32_Processor)

        foreach ($CPU in $CPUs) {
            Write-Log "Processor Name: $($CPU.Name)" "INFO"
            Write-Log "Processor Cores: $($CPU.NumberOfCores)" "INFO"
            Write-Log "Logical Processors: $($CPU.NumberOfLogicalProcessors)" "INFO"
            Write-Log "Maximum Clock Speed: $($CPU.MaxClockSpeed) MHz" "INFO"
            Write-Log "Current Clock Speed: $($CPU.CurrentClockSpeed) MHz" "INFO"
            Write-Log "Socket: $($CPU.SocketDesignation)" "INFO"

            Add-ReportData @{
                "Processor Name"    = $CPU.Name
                "Cores"             = $CPU.NumberOfCores
                "Logical Processors" = $CPU.NumberOfLogicalProcessors
                "Max Speed MHz"     = $CPU.MaxClockSpeed
            }
        }
    }
    catch {
        Write-Log "Error retrieving processor information: $($_.Exception.Message)" "ERROR"
    }

    Write-Log "" "INFO"
}

function Get-MemoryInfo {
    Write-Log "MEMORY INFORMATION" "INFO"
    Show-Separator

    try {
        $Computer = Get-CimInstance -ClassName Win32_ComputerSystem
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem

        $TotalMemoryGB = Convert-BytesToGB $Computer.TotalPhysicalMemory
        $FreeMemoryGB = Convert-BytesToGB ($OS.FreePhysicalMemory * 1KB)
        $UsedMemoryGB = [math]::Round(($TotalMemoryGB - $FreeMemoryGB), 2)

        if ($OS.TotalVisibleMemorySize -gt 0) {
            $MemoryUsagePercent = [math]::Round(
                (($OS.TotalVisibleMemorySize - $OS.FreePhysicalMemory) /
                $OS.TotalVisibleMemorySize) * 100,
                2
            )
        }
        else {
            $MemoryUsagePercent = 0
        }

        Write-Log "Total Physical Memory: $TotalMemoryGB GB" "INFO"
        Write-Log "Used Memory: $UsedMemoryGB GB" "INFO"
        Write-Log "Free Memory: $FreeMemoryGB GB" "INFO"
        Write-Log "Memory Usage: $MemoryUsagePercent%" "INFO"

        $RAMModules = @(Get-CimInstance -ClassName Win32_PhysicalMemory)

        Write-Log "RAM Modules Installed: $($RAMModules.Count)" "INFO"

        foreach ($Module in $RAMModules) {
            $ModuleSizeGB = Convert-BytesToGB $Module.Capacity
            Write-Log "RAM: $($Module.Manufacturer) - $ModuleSizeGB GB - $($Module.Speed) MHz" "INFO"
        }

        Add-ReportData @{
            "Total Memory GB" = $TotalMemoryGB
            "Used Memory GB"  = $UsedMemoryGB
            "Free Memory GB"  = $FreeMemoryGB
            "Memory Usage %"  = $MemoryUsagePercent
            "RAM Modules"     = $RAMModules.Count
        }
    }
    catch {
        Write-Log "Error retrieving memory information: $($_.Exception.Message)" "ERROR"
    }

    Write-Log "" "INFO"
}

function Get-DiskInfo {
    Write-Log "DISK INFORMATION" "INFO"
    Show-Separator

    try {
        $Disks = @(Get-CimInstance -ClassName Win32_LogicalDisk |
            Where-Object { $_.DriveType -eq 3 })

        foreach ($Disk in $Disks) {
            if ($Disk.Size -le 0) {
                continue
            }

            $DriveName = $Disk.DeviceID
            $TotalGB = Convert-BytesToGB $Disk.Size
            $FreeGB = Convert-BytesToGB $Disk.FreeSpace
            $UsedGB = [math]::Round(($TotalGB - $FreeGB), 2)
            $UsagePercent = [math]::Round(($UsedGB / $TotalGB) * 100, 2)

            if ($UsagePercent -lt 70) {
                $Status = "SUCCESS"
            }
            elseif ($UsagePercent -lt 90) {
                $Status = "WARNING"
            }
            else {
                $Status = "ERROR"
            }

            Write-Log "Drive: $DriveName" "INFO"
            Write-Log "  Total: $TotalGB GB" "INFO"
            Write-Log "  Used: $UsedGB GB" "INFO"
            Write-Log "  Free: $FreeGB GB" "INFO"
            Write-Log "  Usage: $UsagePercent%" $Status

            Add-ReportData @{
                "Drive $DriveName Total GB" = $TotalGB
                "Drive $DriveName Used GB"  = $UsedGB
                "Drive $DriveName Free GB"  = $FreeGB
                "Drive $DriveName Usage %"  = $UsagePercent
            }
        }
    }
    catch {
        Write-Log "Error retrieving disk information: $($_.Exception.Message)" "ERROR"
    }

    Write-Log "" "INFO"
}

function Get-GPUInfo {
    Write-Log "GRAPHICS INFORMATION" "INFO"
    Show-Separator

    try {
        $GPUs = @(Get-CimInstance -ClassName Win32_VideoController)

        if ($GPUs.Count -eq 0) {
            Write-Log "No graphics adapter information found." "WARNING"
        }

        foreach ($GPU in $GPUs) {
            $VRAMMB = 0

            if ($GPU.AdapterRAM) {
                $VRAMMB = [math]::Round(($GPU.AdapterRAM / 1MB), 2)
            }

            $Resolution = "$($GPU.CurrentHorizontalResolution)x$($GPU.CurrentVerticalResolution)"

            Write-Log "GPU Name: $($GPU.Name)" "INFO"
            Write-Log "Driver Version: $($GPU.DriverVersion)" "INFO"
            Write-Log "VRAM: $VRAMMB MB" "INFO"
            Write-Log "Current Resolution: $Resolution" "INFO"
            Write-Log "Refresh Rate: $($GPU.CurrentRefreshRate) Hz" "INFO"

            Add-ReportData @{
                "GPU Name"       = $GPU.Name
                "GPU Driver"     = $GPU.DriverVersion
                "GPU VRAM MB"    = $VRAMMB
                "GPU Resolution" = $Resolution
            }
        }
    }
    catch {
        Write-Log "Error retrieving graphics information: $($_.Exception.Message)" "ERROR"
    }

    Write-Log "" "INFO"
}

function Get-NetworkInfo {
    Write-Log "NETWORK INFORMATION" "INFO"
    Show-Separator

    try {
        $Adapters = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration |
            Where-Object { $_.IPEnabled -eq $true })

        foreach ($Adapter in $Adapters) {
            $IPAddresses = ($Adapter.IPAddress -join ", ")
            $SubnetMasks = ($Adapter.IPSubnet -join ", ")
            $Gateways = ($Adapter.DefaultIPGateway -join ", ")

            Write-Log "Adapter: $($Adapter.Description)" "INFO"
            Write-Log "MAC Address: $($Adapter.MACAddress)" "INFO"
            Write-Log "IP Address: $IPAddresses" "INFO"
            Write-Log "Subnet Mask: $SubnetMasks" "INFO"
            Write-Log "Default Gateway: $Gateways" "INFO"

            Add-ReportData @{
                "Network Adapter" = $Adapter.Description
                "MAC Address"     = $Adapter.MACAddress
                "IP Address"      = $IPAddresses
            }
        }
    }
    catch {
        Write-Log "Error retrieving network information: $($_.Exception.Message)" "ERROR"
    }

    Write-Log "" "INFO"
}

function Get-BatteryInfo {
    Write-Log "BATTERY INFORMATION" "INFO"
    Show-Separator

    try {
        $Batteries = @(Get-CimInstance -ClassName Win32_Battery)

        if ($Batteries.Count -eq 0) {
            Write-Log "No battery detected. This may be a desktop system." "INFO"
        }
        else {
            foreach ($Battery in $Batteries) {
                Write-Log "Battery: $($Battery.Name)" "INFO"
                Write-Log "Status: $($Battery.Status)" "INFO"
                Write-Log "Charge Level: $($Battery.EstimatedChargeRemaining)%" "INFO"
                Write-Log "Battery Status Code: $($Battery.BatteryStatus)" "INFO"
                Write-Log "Chemistry Code: $($Battery.Chemistry)" "INFO"

                Add-ReportData @{
                    "Battery Name"   = $Battery.Name
                    "Battery Charge %" = $Battery.EstimatedChargeRemaining
                    "Battery Status" = $Battery.Status
                }
            }
        }
    }
    catch {
        Write-Log "Error retrieving battery information: $($_.Exception.Message)" "ERROR"
    }

    Write-Log "" "INFO"
}

function Get-BIOSInfo {
    Write-Log "BIOS AND FIRMWARE INFORMATION" "INFO"
    Show-Separator

    try {
        $BIOS = Get-CimInstance -ClassName Win32_BIOS
        $BaseBoard = Get-CimInstance -ClassName Win32_BaseBoard

        Write-Log "BIOS Manufacturer: $($BIOS.Manufacturer)" "INFO"
        Write-Log "BIOS Version: $($BIOS.SMBIOSBIOSVersion)" "INFO"
        Write-Log "BIOS Release Date: $($BIOS.ReleaseDate)" "INFO"
        Write-Log "Serial Number: $($BIOS.SerialNumber)" "INFO"
        Write-Log "Motherboard Manufacturer: $($BaseBoard.Manufacturer)" "INFO"
        Write-Log "Motherboard Model: $($BaseBoard.Product)" "INFO"
        Write-Log "System SKU: $($BaseBoard.SKU)" "INFO"

        Add-ReportData @{
            "BIOS Manufacturer" = $BIOS.Manufacturer
            "BIOS Version"      = $BIOS.SMBIOSBIOSVersion
            "Motherboard"       = "$($BaseBoard.Manufacturer) $($BaseBoard.Product)"
            "Serial Number"     = $BIOS.SerialNumber
        }
    }
    catch {
        Write-Log "Error retrieving BIOS information: $($_.Exception.Message)" "ERROR"
    }

    Write-Log "" "INFO"
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

function Export-ToHTML {
    Write-Log "Generating HTML report..." "INFO"

    $HTML = New-Object System.Text.StringBuilder

    [void]$HTML.AppendLine("<!DOCTYPE html>")
    [void]$HTML.AppendLine("<html>")
    [void]$HTML.AppendLine("<head>")
    [void]$HTML.AppendLine("<meta charset='UTF-8'>")
    [void]$HTML.AppendLine("<title>System Information Report</title>")
    [void]$HTML.AppendLine(@"
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
    border-radius: 6px;
}
.section {
    background-color: white;
    padding: 15px;
    margin-top: 15px;
    border-radius: 6px;
    box-shadow: 0 2px 5px rgba(0,0,0,0.15);
}
.section h2 {
    color: #0078d4;
    border-bottom: 2px solid #0078d4;
    padding-bottom: 8px;
}
.info-row {
    padding: 7px 0;
    border-bottom: 1px solid #eeeeee;
    white-space: pre-wrap;
}
.footer {
    text-align: center;
    color: #777777;
    margin-top: 25px;
    font-size: 12px;
}
</style>
"@)
    [void]$HTML.AppendLine("</head>")
    [void]$HTML.AppendLine("<body>")
    [void]$HTML.AppendLine("<div class='header'>")
    [void]$HTML.AppendLine("<h1>System Information Report</h1>")
    [void]$HTML.AppendLine("<p>Generated: $(Escape-Html (Get-Date))</p>")
    [void]$HTML.AppendLine("</div>")

    $CurrentSection = "General Information"

    foreach ($Line in Get-Content -LiteralPath $TextReportFile) {
        if ($Line -match "^\[.*\] \[(INFO|WARNING|ERROR|SUCCESS)\] (.+)$") {
            $Message = $Matches[2]

            if ($Message -match "^[A-Z][A-Z\s]+$" -and $Message.Length -gt 3) {
                $CurrentSection = $Message
                [void]$HTML.AppendLine("<div class='section'>")
                [void]$HTML.AppendLine("<h2>$(Escape-Html $CurrentSection)</h2>")
            }
            elseif ($Message -notmatch "^=+$") {
                [void]$HTML.AppendLine(
                    "<div class='info-row'>$(Escape-Html $Message)</div>"
                )
            }
        }
    }

    [void]$HTML.AppendLine("</div>")
    [void]$HTML.AppendLine("<div class='footer'>")
    [void]$HTML.AppendLine("System Information Report")
    [void]$HTML.AppendLine("</div>")
    [void]$HTML.AppendLine("</body>")
    [void]$HTML.AppendLine("</html>")

    Set-Content -LiteralPath $HTMLReportFile -Value $HTML.ToString() -Encoding UTF8

    Write-Log "HTML report saved: $HTMLReportFile" "SUCCESS"
}

function Update-MetricsHistory {
    Write-Log "Updating metrics history..." "INFO"

    try {
        if (-not (Test-Path -LiteralPath $CSVHistoryFile)) {
            $Header = @(
                "Timestamp",
                "Computer Name",
                "Total Memory GB",
                "Used Memory GB",
                "Memory Usage %",
                "C: Drive Usage %",
                "D: Drive Usage %",
                "System Uptime Days",
                "CPU Name",
                "GPU Name"
            )

            ($Header -join ",") |
                Set-Content -LiteralPath $CSVHistoryFile -Encoding UTF8
        }

        $Row = [pscustomobject]@{
            Timestamp             = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "Computer Name"       = Get-FirstReportValue "Computer Name"
            "Total Memory GB"     = Get-FirstReportValue "Total Memory GB"
            "Used Memory GB"      = Get-FirstReportValue "Used Memory GB"
            "Memory Usage %"      = Get-FirstReportValue "Memory Usage %"
            "C: Drive Usage %"    = Get-FirstReportValue "Drive C: Usage %"
            "D: Drive Usage %"    = Get-FirstReportValue "Drive D: Usage %"
            "System Uptime Days"  = Get-FirstReportValue "Uptime Days"
            "CPU Name"            = Get-FirstReportValue "Processor Name"
            "GPU Name"            = Get-FirstReportValue "GPU Name"
        }

        $CSVLine = ($Row.PSObject.Properties.Value | ForEach-Object {
            $Value = [string]$_

            if ($Value -match '[,"\r\n]') {
                '"' + ($Value -replace '"', '""') + '"'
            }
            else {
                $Value
            }
        }) -join ","

        Add-Content -LiteralPath $CSVHistoryFile -Value $CSVLine -Encoding UTF8

        Write-Log "Metrics history updated: $CSVHistoryFile" "SUCCESS"
    }
    catch {
        Write-Log "Error updating metrics history: $($_.Exception.Message)" "WARNING"
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Main {
    try {
        Write-Log "================================================================" "INFO"
        Write-Log "SYSTEM INFORMATION AND HEALTH REPORT" "INFO"
        Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
        Write-Log "Output Directory: $LogPath" "INFO"
        Write-Log "Text Report: $TextReportFile" "INFO"
        Show-Separator

        Get-SystemInfo
        Get-ProcessorInfo
        Get-MemoryInfo
        Get-DiskInfo
        Get-GPUInfo
        Get-NetworkInfo
        Get-BatteryInfo
        Get-BIOSInfo

        Write-Log "EXPORTING REPORTS" "INFO"
        Show-Separator

        Export-ToHTML
        Update-MetricsHistory

        Write-Log "" "INFO"
        Show-Separator
        Write-Log "REPORT GENERATION COMPLETE" "SUCCESS"
        Write-Log "Text Report: $TextReportFile" "SUCCESS"
        Write-Log "HTML Report: $HTMLReportFile" "SUCCESS"
        Write-Log "History File: $CSVHistoryFile" "SUCCESS"
        Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
        Write-Log "================================================================" "INFO"
    }
    catch {
        Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

Main
