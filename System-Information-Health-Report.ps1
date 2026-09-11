<#
.SYNOPSIS
    System Information and Health Report Script
    Generates comprehensive hardware and system health report

.DESCRIPTION
    This script generates a detailed system health report including:
    - Hardware inventory (CPU, RAM, Disk, GPU)
    - OS version and build information
    - System uptime and last restart date
    - Disk usage by drive
    - RAM usage and available memory
    - Battery health (if laptop)
    - Network adapter information
    - Display resolution and graphics
    - BIOS and firmware information
    - Export to HTML report for easy viewing
    - Track metrics over time
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Report files: $env:USERPROFILE\Documents\SystemReport_YYYYMMDD_HHmmss.*

.AUTHOR
    System Information Report Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$ReportTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$TextReportFile = Join-Path -Path $LogPath -ChildPath "SystemReport_$ReportTimestamp.txt"
$HTMLReportFile = Join-Path -Path $LogPath -ChildPath "SystemReport_$ReportTimestamp.html"
$CSVHistoryFile = Join-Path -Path $LogPath -ChildPath "SystemMetricsHistory.csv"

# Initialize report data
$ReportData = @()

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
    
    # Write to text report
    Add-Content -Path $TextReportFile -Value $logMessage
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

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Retrieve system information
    #>
    Write-Log "SYSTEM INFORMATION" "INFO"
    Show-Separator
    
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
        
        $osName = $osInfo.Caption
        $osVersion = $osInfo.Version
        $osBuild = $osInfo.BuildNumber
        $computerName = $computerInfo.Name
        $domain = $computerInfo.Domain
        $systemType = $computerInfo.SystemType
        
        Write-Log "Computer Name: $computerName" "INFO"
        Write-Log "Domain/Workgroup: $domain" "INFO"
        Write-Log "Operating System: $osName" "INFO"
        Write-Log "OS Version: $osVersion" "INFO"
        Write-Log "OS Build: $osBuild" "INFO"
        Write-Log "System Type: $systemType" "INFO"
        
        # Calculate uptime
        $lastBootTime = $osInfo.LastBootUpTime
        $currentTime = Get-Date
        $uptime = $currentTime - $lastBootTime
        
        Write-Log "Last Boot Time: $lastBootTime" "INFO"
        Write-Log "System Uptime: $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes" "INFO"
        
        $ReportData += @{
            "Computer Name" = $computerName
            "OS Name" = $osName
            "OS Version" = $osVersion
            "OS Build" = $osBuild
            "Uptime Days" = $uptime.Days
            "Last Boot" = $lastBootTime
        }
    }
    catch {
        Write-Log "Error retrieving system information: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Get-ProcessorInfo {
    <#
    .SYNOPSIS
        Retrieve CPU information
    #>
    Write-Log "PROCESSOR INFORMATION" "INFO"
    Show-Separator
    
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor
        
        Write-Log "Processor Name: $($cpu.Name)" "INFO"
        Write-Log "Processor Cores: $($cpu.NumberOfCores)" "INFO"
        Write-Log "Logical Processors: $($cpu.NumberOfLogicalProcessors)" "INFO"
        Write-Log "Max Clock Speed: $($cpu.MaxClockSpeed) MHz" "INFO"
        Write-Log "Current Clock Speed: $($cpu.CurrentClockSpeed) MHz" "INFO"
        Write-Log "Socket: $($cpu.SocketDesignation)" "INFO"
        
        $ReportData += @{
            "Processor Name" = $cpu.Name
            "Cores" = $cpu.NumberOfCores
            "Logical Processors" = $cpu.NumberOfLogicalProcessors
            "Max Speed MHz" = $cpu.MaxClockSpeed
        }
    }
    catch {
        Write-Log "Error retrieving processor information: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Get-MemoryInfo {
    <#
    .SYNOPSIS
        Retrieve memory (RAM) information
    #>
    Write-Log "MEMORY INFORMATION" "INFO"
    Show-Separator
    
    try {
        $totalMemory = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory
        $totalMemoryGB = Convert-BytesToGB -Bytes $totalMemory
        
        # Get used memory
        $memoryStats = Get-CimInstance -ClassName Win32_OperatingSystem
        $usedMemory = $memoryStats.TotalVisibleMemorySize - $memoryStats.FreePhysicalMemory
        $usedMemoryKB = $memoryStats.TotalVisibleMemorySize * 1024 - $memoryStats.FreePhysicalMemory * 1024
        $usedMemoryGB = Convert-BytesToGB -Bytes ($usedMemoryKB * 1024)
        $freeMemoryGB = Convert-BytesToGB -Bytes ($memoryStats.FreePhysicalMemory * 1024 * 1024)
        $memoryUsagePercent = [math]::Round(($usedMemory / $memoryStats.TotalVisibleMemorySize) * 100, 2)
        
        Write-Log "Total Physical Memory: $totalMemoryGB GB" "INFO"
        Write-Log "Used Memory: $usedMemoryGB GB" "INFO"
        Write-Log "Free Memory: $freeMemoryGB GB" "INFO"
        Write-Log "Memory Usage: $memoryUsagePercent%" "INFO"
        
        # Get RAM module details
        $ramModules = Get-CimInstance -ClassName Win32_PhysicalMemory
        Write-Log "RAM Modules Installed: $($ramModules.Count)" "INFO"
        
        foreach ($module in $ramModules) {
            $moduleSize = Convert-BytesToGB -Bytes $module.Capacity
            Write-Log "  • $($module.Manufacturer) - $moduleSize GB - $($module.Speed) MHz" "INFO"
        }
        
        $ReportData += @{
            "Total Memory GB" = $totalMemoryGB
            "Used Memory GB" = $usedMemoryGB
            "Free Memory GB" = $freeMemoryGB
            "Memory Usage %" = $memoryUsagePercent
            "RAM Modules" = $ramModules.Count
        }
    }
    catch {
        Write-Log "Error retrieving memory information: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Get-DiskInfo {
    <#
    .SYNOPSIS
        Retrieve disk information
    #>
    Write-Log "DISK INFORMATION" "INFO"
    Show-Separator
    
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        
        foreach ($disk in $disks) {
            $driveName = $disk.Name
            $totalSize = Convert-BytesToGB -Bytes $disk.Size
            $freeSpace = Convert-BytesToGB -Bytes $disk.FreeSpace
            $usedSpace = $totalSize - $freeSpace
            $usagePercent = [math]::Round(($usedSpace / $totalSize) * 100, 2)
            
            $statusColor = if ($usagePercent -lt 70) { "SUCCESS" } elseif ($usagePercent -lt 90) { "WARNING" } else { "ERROR" }
            
            Write-Log "Drive: $driveName" "INFO"
            Write-Log "  Total: $totalSize GB" "INFO"
            Write-Log "  Used: $usedSpace GB" "INFO"
            Write-Log "  Free: $freeSpace GB" "INFO"
            Write-Log "  Usage: $usagePercent%" $statusColor
            
            $ReportData += @{
                "Drive $driveName Total GB" = $totalSize
                "Drive $driveName Used GB" = $usedSpace
                "Drive $driveName Free GB" = $freeSpace
                "Drive $driveName Usage %" = $usagePercent
            }
        }
    }
    catch {
        Write-Log "Error retrieving disk information: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Get-GPUInfo {
    <#
    .SYNOPSIS
        Retrieve graphics card information
    #>
    Write-Log "GRAPHICS INFORMATION" "INFO"
    Show-Separator
    
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController
        
        if ($null -ne $gpus) {
            foreach ($gpu in $gpus) {
                Write-Log "GPU Name: $($gpu.Name)" "INFO"
                Write-Log "  Driver Version: $($gpu.DriverVersion)" "INFO"
                Write-Log "  VRAM: $($gpu.AdapterRAM / 1MB) MB" "INFO"
                Write-Log "  Current Resolution: $($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution)" "INFO"
                Write-Log "  Refresh Rate: $($gpu.CurrentRefreshRate) Hz" "INFO"
                
                $ReportData += @{
                    "GPU Name" = $gpu.Name
                    "GPU Driver" = $gpu.DriverVersion
                    "GPU VRAM MB" = $gpu.AdapterRAM / 1MB
                }
            }
        }
    }
    catch {
        Write-Log "Error retrieving GPU information: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Get-NetworkInfo {
    <#
    .SYNOPSIS
        Retrieve network adapter information
    #>
    Write-Log "NETWORK INFORMATION" "INFO"
    Show-Separator
    
    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        
        foreach ($adapter in $adapters) {
            Write-Log "Adapter: $($adapter.Description)" "INFO"
            Write-Log "  MAC Address: $($adapter.MACAddress)" "INFO"
            Write-Log "  IP Address: $($adapter.IPAddress -join ', ')" "INFO"
            Write-Log "  Subnet Mask: $($adapter.IPSubnet -join ', ')" "INFO"
            Write-Log "  Default Gateway: $($adapter.DefaultIPGateway -join ', ')" "INFO"
            
            $ReportData += @{
                "Network Adapter" = $adapter.Description
                "MAC Address" = $adapter.MACAddress
                "IP Address" = $adapter.IPAddress -join ', '
            }
        }
    }
    catch {
        Write-Log "Error retrieving network information: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Get-BatteryInfo {
    <#
    .SYNOPSIS
        Retrieve battery information (if applicable)
    #>
    Write-Log "BATTERY INFORMATION" "INFO"
    Show-Separator
    
    try {
        $batteries = Get-CimInstance -ClassName Win32_Battery
        
        if ($null -ne $batteries) {
            foreach ($battery in $batteries) {
                Write-Log "Battery: $($battery.Name)" "INFO"
                Write-Log "  Status: $($battery.Status)" "INFO"
                Write-Log "  Charge Level: $($battery.EstimatedChargeRemaining)%" "INFO"
                Write-Log "  Health Status: $($battery.BatteryStatus)" "INFO"
                Write-Log "  Chemistry: $($battery.Chemistry)" "INFO"
                
                $ReportData += @{
                    "Battery Name" = $battery.Name
                    "Battery Charge %" = $battery.EstimatedChargeRemaining
                    "Battery Health" = $battery.BatteryStatus
                }
            }
        } else {
            Write-Log "No battery detected (Desktop system)" "INFO"
        }
    }
    catch {
        Write-Log "Error retrieving battery information: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Get-BIOSInfo {
    <#
    .SYNOPSIS
        Retrieve BIOS and firmware information
    #>
    Write-Log "BIOS AND FIRMWARE INFORMATION" "INFO"
    Show-Separator
    
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS
        $systemBoard = Get-CimInstance -ClassName Win32_BaseBoard
        
        Write-Log "BIOS Manufacturer: $($bios.Manufacturer)" "INFO"
        Write-Log "BIOS Version: $($bios.SMBIOSBIOSVersion)" "INFO"
        Write-Log "BIOS Release Date: $($bios.ReleaseDate)" "INFO"
        Write-Log "Serial Number: $($bios.SerialNumber)" "INFO"
        Write-Log "Motherboard Manufacturer: $($systemBoard.Manufacturer)" "INFO"
        Write-Log "Motherboard Model: $($systemBoard.Product)" "INFO"
        Write-Log "System SKU: $($systemBoard.SKU)" "INFO"
        
        $ReportData += @{
            "BIOS Manufacturer" = $bios.Manufacturer
            "BIOS Version" = $bios.SMBIOSBIOSVersion
            "Motherboard" = "$($systemBoard.Manufacturer) $($systemBoard.Product)"
            "Serial Number" = $bios.SerialNumber
        }
    }
    catch {
        Write-Log "Error retrieving BIOS information: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Export-ToHTML {
    <#
    .SYNOPSIS
        Export report data to HTML format
    #>
    Write-Log "Generating HTML report..." "INFO"
    
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Information Report</title>
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
        .info-row {
            padding: 8px 0;
            border-bottom: 1px solid #eee;
        }
        .info-row:last-child {
            border-bottom: none;
        }
        .label {
            font-weight: bold;
            color: #333;
            display: inline-block;
            width: 200px;
        }
        .value {
            color: #666;
        }
        .footer {
            text-align: center;
            color: #999;
            margin-top: 30px;
            font-size: 12px;
        }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        .error { color: #dc3545; }
    </style>
</head>
<body>
    <div class="header">
        <h1>System Information Report</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
"@
    
    # Add report sections
    $sections = @{
        "System" = "System Information";
        "Processor" = "CPU Information";
        "Memory" = "RAM Information";
        "Disk" = "Storage";
        "GPU" = "Graphics";
        "Network" = "Network";
        "Battery" = "Battery";
        "BIOS" = "Firmware"
    }
    
    # Read text report and organize into sections
    $textContent = Get-Content -Path $TextReportFile
    $currentSection = ""
    $sectionContent = ""
    
    foreach ($line in $textContent) {
        if ($line -match "^=+$") {
            if ($sectionContent) {
                $htmlContent += "<div class='section'><h2>$currentSection</h2>"
                foreach ($contentLine in $sectionContent -split "`n") {
                    if ($contentLine.Trim()) {
                        $htmlContent += "<div class='info-row'>$($contentLine -replace '<', '&lt;' -replace '>', '&gt;')</div>"
                    }
                }
                $htmlContent += "</div>"
            }
            $sectionContent = ""
        } elseif ($line -match "\[INFO\]|\[SUCCESS\]|\[WARNING\]|\[ERROR\]") {
            $sectionContent += $line + "`n"
        }
    }
    
    $htmlContent += @"
    <div class="footer">
        <p>System Information Report | Generated by PowerShell Maintenance Suite</p>
    </div>
</body>
</html>
"@
    
    Set-Content -Path $HTMLReportFile -Value $htmlContent
    Write-Log "✓ HTML report saved: $HTMLReportFile" "SUCCESS"
}

function Update-MetricsHistory {
    <#
    .SYNOPSIS
        Update historical metrics CSV file
    #>
    Write-Log "Updating metrics history..." "INFO"
    
    try {
        # Create header if file doesn't exist
        if (-not (Test-Path -Path $CSVHistoryFile)) {
            $header = "Timestamp,Computer Name,Total Memory GB,Used Memory GB,Memory Usage %,C: Drive Usage %,D: Drive Usage %,System Uptime Days,CPU Name,GPU Name"
            Set-Content -Path $CSVHistoryFile -Value $header
        }
        
        # Extract values from ReportData
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $computerName = ($ReportData | Where-Object { $_.Keys -contains "Computer Name" }).Values | Select-Object -First 1
        $totalMemory = ($ReportData | Where-Object { $_.Keys -contains "Total Memory GB" }).Values | Select-Object -First 1
        $usedMemory = ($ReportData | Where-Object { $_.Keys -contains "Used Memory GB" }).Values | Select-Object -First 1
        $memoryUsage = ($ReportData | Where-Object { $_.Keys -contains "Memory Usage %" }).Values | Select-Object -First 1
        $cDriveUsage = ($ReportData | Where-Object { $_.Keys -contains "Drive C: Usage %" }).Values | Select-Object -First 1
        $dDriveUsage = ($ReportData | Where-Object { $_.Keys -contains "Drive D: Usage %" }).Values | Select-Object -First 1
        $uptime = ($ReportData | Where-Object { $_.Keys -contains "Uptime Days" }).Values | Select-Object -First 1
        $cpuName = ($ReportData | Where-Object { $_.Keys -contains "Processor Name" }).Values | Select-Object -First 1
        $gpuName = ($ReportData | Where-Object { $_.Keys -contains "GPU Name" }).Values | Select-Object -First 1
        
        # Append new data
        $csvRow = "$timestamp,$computerName,$totalMemory,$usedMemory,$memoryUsage,$cDriveUsage,$dDriveUsage,$uptime,$cpuName,$gpuName"
        Add-Content -Path $CSVHistoryFile -Value $csvRow
        
        Write-Log "✓ Metrics history updated: $CSVHistoryFile" "SUCCESS"
    }
    catch {
        Write-Log "Error updating metrics history: $_" "WARNING"
    }
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize report file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "SYSTEM INFORMATION AND HEALTH REPORT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Report File: $TextReportFile" "INFO"
    Show-Separator
    
    # ===== GATHER SYSTEM INFORMATION =====
    Get-SystemInfo
    Get-ProcessorInfo
    Get-MemoryInfo
    Get-DiskInfo
    Get-GPUInfo
    Get-NetworkInfo
    Get-BatteryInfo
    Get-BIOSInfo
    
    Show-Separator
    Write-Log "" "INFO"
    
    # ===== EXPORT REPORTS =====
    Write-Log "EXPORTING REPORTS" "INFO"
    Show-Separator
    
    Export-ToHTML
    Update-MetricsHistory
    
    Write-Log "" "INFO"
    Show-Separator
    
    # ===== COMPLETION SUMMARY =====
    Write-Log "REPORT GENERATION COMPLETE" "INFO"
    Show-Separator
    
    Write-Log "Reports generated successfully" "SUCCESS"
    Write-Log "" "INFO"
    Write-Log "Text Report: $TextReportFile" "SUCCESS"
    Write-Log "HTML Report: $HTMLReportFile" "SUCCESS"
    Write-Log "History File: $CSVHistoryFile" "SUCCESS"
    Write-Log "" "INFO"
    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "================================================================" "INFO"
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Run main function
Main
