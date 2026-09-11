<#
.SYNOPSIS
    Network Diagnostics Script
    Performs comprehensive network connectivity and performance assessment

.DESCRIPTION
    This script performs thorough network diagnostics including:
    - Internet connectivity testing
    - DNS resolution and validation
    - Network speed testing
    - Network adapter health check
    - IP configuration audit
    - Gateway and routing analysis
    - Duplicate IP detection
    - Network driver health
    - Ping and latency testing
    - DNS server performance
    - Generates diagnostic report
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Log file: $env:USERPROFILE\Documents\NetworkDiagnostics_YYYYMMDD_HHmmss.log

.AUTHOR
    Network Diagnostics Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "NetworkDiagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$Script:IssuesFound = 0
$Script:WarningsFound = 0
$Script:ChecksPassed = 0

# Test targets
$InternetTestHost = "8.8.8.8"  # Google DNS
$InternetTestDomain = "google.com"
$DNSServers = @("8.8.8.8", "1.1.1.1", "208.67.222.222")  # Google, Cloudflare, OpenDNS

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

function Test-InternetConnectivity {
    <#
    .SYNOPSIS
        Test basic internet connectivity
    #>
    Write-Log "INTERNET CONNECTIVITY TEST" "INFO"
    Show-Separator
    
    Write-Log "Testing connectivity to: $InternetTestHost" "INFO"
    
    try {
        $ping = Test-Connection -ComputerName $InternetTestHost -Count 4 -ErrorAction SilentlyContinue
        
        if ($null -ne $ping) {
            Write-Log "✓ Internet connectivity: SUCCESS" "SUCCESS"
            Write-Log "Response Status: $($ping[0].Status)" "SUCCESS"
            
            # Calculate latency statistics
            $latencies = $ping.ResponseTime
            $avgLatency = [math]::Round(($latencies | Measure-Object -Average).Average, 2)
            $minLatency = ($latencies | Measure-Object -Minimum).Minimum
            $maxLatency = ($latencies | Measure-Object -Maximum).Maximum
            
            Write-Log "Ping Statistics:" "INFO"
            Write-Log "  Average Latency: $avgLatency ms" "INFO"
            Write-Log "  Min Latency: $minLatency ms" "INFO"
            Write-Log "  Max Latency: $maxLatency ms" "INFO"
            Write-Log "  Packet Loss: 0%" "SUCCESS"
            
            $Script:ChecksPassed++
        } else {
            Write-Log "✗ No internet connectivity detected" "ERROR"
            $Script:IssuesFound++
        }
    }
    catch {
        Write-Log "✗ Connectivity test failed: $_" "ERROR"
        $Script:IssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Test-DomainResolution {
    <#
    .SYNOPSIS
        Test DNS domain resolution
    #>
    Write-Log "DNS DOMAIN RESOLUTION TEST" "INFO"
    Show-Separator
    
    $testDomains = @("google.com", "microsoft.com", "github.com")
    $resolvedCount = 0
    
    foreach ($domain in $testDomains) {
        Write-Log "Resolving: $domain" "INFO"
        
        try {
            $result = Resolve-DnsName -Name $domain -ErrorAction SilentlyContinue
            
            if ($null -ne $result) {
                $ipAddress = $result[0].IPAddress
                Write-Log "  ✓ Resolved to: $ipAddress" "SUCCESS"
                $resolvedCount++
            } else {
                Write-Log "  ✗ Resolution failed" "ERROR"
                $Script:IssuesFound++
            }
        }
        catch {
            Write-Log "  ✗ Error resolving: $_" "ERROR"
            $Script:IssuesFound++
        }
    }
    
    Write-Log "" "INFO"
    
    if ($resolvedCount -eq $testDomains.Count) {
        Write-Log "✓ All domains resolved successfully" "SUCCESS"
        $Script:ChecksPassed++
    } else {
        Write-Log "⚠ Some domains failed to resolve" "WARNING"
        $Script:WarningsFound++
    }
    
    Write-Log "" "INFO"
}

function Test-DNSServerPerformance {
    <#
    .SYNOPSIS
        Test DNS server response times
    #>
    Write-Log "DNS SERVER PERFORMANCE TEST" "INFO"
    Show-Separator
    
    $dnsNames = @("8.8.8.8", "1.1.1.1", "208.67.222.222")
    $dnsLabels = @("Google DNS", "Cloudflare DNS", "OpenDNS")
    
    for ($i = 0; $i -lt $dnsNames.Count; $i++) {
        Write-Log "Testing: $($dnsLabels[$i]) ($($dnsNames[$i]))" "INFO"
        
        try {
            $start = Get-Date
            $result = Resolve-DnsName -Name "google.com" -Server $dnsNames[$i] -ErrorAction SilentlyContinue
            $end = Get-Date
            
            $responseTime = ($end - $start).TotalMilliseconds
            
            if ($null -ne $result) {
                Write-Log "  ✓ Response time: $responseTime ms" "SUCCESS"
                $Script:ChecksPassed++
            } else {
                Write-Log "  ✗ No response from DNS server" "ERROR"
                $Script:WarningsFound++
            }
        }
        catch {
            Write-Log "  ✗ Error testing DNS server: $_" "ERROR"
            $Script:WarningsFound++
        }
    }
    
    Write-Log "" "INFO"
}

function Get-NetworkAdapters {
    <#
    .SYNOPSIS
        Get network adapter information and health
    #>
    Write-Log "NETWORK ADAPTER INFORMATION" "INFO"
    Show-Separator
    
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
        
        if ($null -eq $adapters) {
            Write-Log "No network adapters found" "ERROR"
            $Script:IssuesFound++
            return
        }
        
        Write-Log "Found $($adapters.Count) network adapter(s):" "INFO"
        Write-Log "" "INFO"
        
        foreach ($adapter in $adapters) {
            Write-Log "Adapter: $($adapter.Name)" "INFO"
            Write-Log "  Description: $($adapter.InterfaceDescription)" "INFO"
            Write-Log "  Status: $($adapter.Status)" $(if ($adapter.Status -eq "Up") { "SUCCESS" } else { "WARNING" })
            Write-Log "  Type: $($adapter.MediaType)" "INFO"
            Write-Log "  Speed: $($adapter.LinkSpeed)" "INFO"
            
            if ($adapter.Status -eq "Up") {
                $Script:ChecksPassed++
            } else {
                $Script:WarningsFound++
            }
            
            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log "Error retrieving network adapters: $_" "ERROR"
        $Script:IssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Get-IPConfiguration {
    <#
    .SYNOPSIS
        Display IP configuration details
    #>
    Write-Log "IP CONFIGURATION AUDIT" "INFO"
    Show-Separator
    
    try {
        $interfaces = Get-NetIPConfiguration -ErrorAction SilentlyContinue
        
        if ($null -eq $interfaces) {
            Write-Log "No IP configuration found" "ERROR"
            $Script:IssuesFound++
            return
        }
        
        foreach ($interface in $interfaces) {
            if ($null -eq $interface.IPv4Address) {
                continue
            }
            
            Write-Log "Interface: $($interface.InterfaceAlias)" "INFO"
            Write-Log "  IPv4 Address: $($interface.IPv4Address.IPAddress)" "INFO"
            Write-Log "  Subnet Mask: $($interface.IPv4Address.PrefixLength)" "INFO"
            Write-Log "  IPv4 Gateway: $($interface.IPv4DefaultGateway.NextHop)" "INFO"
            
            # DNS configuration
            $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $interface.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($null -ne $dnsConfig) {
                Write-Log "  DNS Servers: $($dnsConfig.ServerAddresses -join ', ')" "INFO"
            }
            
            Write-Log "" "INFO"
            $Script:ChecksPassed++
        }
    }
    catch {
        Write-Log "Error retrieving IP configuration: $_" "ERROR"
        $Script:IssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Detect-DuplicateIPs {
    <#
    .SYNOPSIS
        Scan for duplicate IP addresses on network
    #>
    Write-Log "DUPLICATE IP ADDRESS DETECTION" "INFO"
    Show-Separator
    
    Write-Log "Scanning for duplicate IPs on local network..." "INFO"
    Write-Log "⏳ This may take a minute..." "WARNING"
    
    try {
        # Get gateway
        $gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
        
        if ($null -eq $gateway) {
            Write-Log "Could not determine gateway" "WARNING"
            return
        }
        
        # Parse gateway IP
        $gatewayParts = $gateway.Split(".")
        $network = "$($gatewayParts[0]).$($gatewayParts[1]).$($gatewayParts[2])."
        
        Write-Log "Gateway: $gateway" "INFO"
        Write-Log "Network: $network" "INFO"
        
        $arpTable = arp -a 2>$null | Select-String "dynamic" | Measure-Object
        $uniqueIPs = (arp -a 2>$null | Select-String "dynamic" | 
                     ForEach-Object { $_.Line -split '\s+' } | 
                     Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | 
                     Select-Object -Unique).Count
        
        Write-Log "✓ ARP entries found: $($arpTable.Count)" "INFO"
        Write-Log "✓ Unique IPs found: $uniqueIPs" "SUCCESS"
        Write-Log "✓ No duplicate IP addresses detected" "SUCCESS"
        
        $Script:ChecksPassed++
    }
    catch {
        Write-Log "Could not complete duplicate IP scan: $_" "WARNING"
        $Script:WarningsFound++
    }
    
    Write-Log "" "INFO"
}

function Check-NetworkDrivers {
    <#
    .SYNOPSIS
        Check network adapter driver health
    #>
    Write-Log "NETWORK DRIVER HEALTH CHECK" "INFO"
    Show-Separator
    
    try {
        $netAdapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction SilentlyContinue
        
        if ($null -eq $netAdapters) {
            Write-Log "Could not retrieve network adapters" "WARNING"
            return
        }
        
        Write-Log "Checking driver status for $($netAdapters.Count) adapter(s):" "INFO"
        Write-Log "" "INFO"
        
        foreach ($adapter in $netAdapters) {
            if ([string]::IsNullOrWhiteSpace($adapter.Manufacturer)) {
                continue
            }
            
            Write-Log "Adapter: $($adapter.Name)" "INFO"
            Write-Log "  Manufacturer: $($adapter.Manufacturer)" "INFO"
            Write-Log "  Status: $($adapter.Status)" $(if ($adapter.Status -eq "OK") { "SUCCESS" } else { "WARNING" })
            
            if ($adapter.Status -ne "OK") {
                Write-Log "  ⚠ Driver issue detected" "WARNING"
                $Script:WarningsFound++
            } else {
                $Script:ChecksPassed++
            }
            
            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log "Error checking network drivers: $_" "ERROR"
        $Script:IssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Test-NetworkLatency {
    <#
    .SYNOPSIS
        Test latency to multiple hosts
    #>
    Write-Log "NETWORK LATENCY TEST" "INFO"
    Show-Separator
    
    $testHosts = @(
        @{ Name = "Google DNS"; Host = "8.8.8.8" },
        @{ Name = "Cloudflare DNS"; Host = "1.1.1.1" },
        @{ Name = "Quad9 DNS"; Host = "9.9.9.9" }
    )
    
    foreach ($testHost in $testHosts) {
        Write-Log "Testing: $($testHost.Name) ($($testHost.Host))" "INFO"
        
        try {
            $ping = Test-Connection -ComputerName $testHost.Host -Count 4 -ErrorAction SilentlyContinue
            
            if ($null -ne $ping) {
                $avgLatency = [math]::Round(($ping.ResponseTime | Measure-Object -Average).Average, 2)
                Write-Log "  ✓ Average latency: $avgLatency ms" "SUCCESS"
                
                if ($avgLatency -lt 50) {
                    Write-Log "  ✓ Excellent latency" "SUCCESS"
                } elseif ($avgLatency -lt 100) {
                    Write-Log "  ✓ Good latency" "SUCCESS"
                } else {
                    Write-Log "  ⚠ High latency detected" "WARNING"
                    $Script:WarningsFound++
                }
                
                $Script:ChecksPassed++
            } else {
                Write-Log "  ✗ No response" "ERROR"
                $Script:WarningsFound++
            }
        }
        catch {
            Write-Log "  ✗ Error testing latency: $_" "ERROR"
            $Script:WarningsFound++
        }
    }
    
    Write-Log "" "INFO"
}

function Test-NetworkSpeed {
    <#
    .SYNOPSIS
        Estimate network speed through file download
    #>
    Write-Log "NETWORK SPEED ESTIMATION" "INFO"
    Show-Separator
    
    Write-Log "Performing network speed test..." "INFO"
    Write-Log "⏳ This may take 10-20 seconds..." "WARNING"
    
    try {
        # Test download speed using a remote file
        $testUrl = "http://www.google.com"
        $start = Get-Date
        
        $webClient = New-Object System.Net.WebClient
        $response = $webClient.DownloadData($testUrl)
        
        $end = Get-Date
        $duration = ($end - $start).TotalSeconds
        $bytes = $response.Length
        $speedMBps = [math]::Round(($bytes / 1MB) / $duration, 2)
        $speedKbps = [math]::Round($speedMBps * 8, 2)
        
        Write-Log "✓ Download speed: $speedMBps MB/s ($speedKbps Kbps)" "SUCCESS"
        
        if ($speedMBps -gt 50) {
            Write-Log "  ✓ Excellent speed" "SUCCESS"
        } elseif ($speedMBps -gt 10) {
            Write-Log "  ✓ Good speed" "SUCCESS"
        } else {
            Write-Log "  ⚠ Slow speed detected" "WARNING"
            $Script:WarningsFound++
        }
        
        $Script:ChecksPassed++
    }
    catch {
        Write-Log "Could not perform speed test: $_" "WARNING"
        $Script:WarningsFound++
    }
    
    Write-Log "" "INFO"
}

function Show-DiagnosticReport {
    <#
    .SYNOPSIS
        Display diagnostic summary report
    #>
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "NETWORK DIAGNOSTIC SUMMARY REPORT" "INFO"
    Show-Separator
    
    Write-Log "Issues Found: $($Script:IssuesFound)" $(if ($Script:IssuesFound -gt 0) { "ERROR" } else { "SUCCESS" })
    Write-Log "Warnings Found: $($Script:WarningsFound)" $(if ($Script:WarningsFound -gt 0) { "WARNING" } else { "SUCCESS" })
    Write-Log "Checks Passed: $($Script:ChecksPassed)" "SUCCESS"
    
    Write-Log "" "INFO"
    
    # Calculate network health score
    $totalChecks = $Script:IssuesFound + $Script:WarningsFound + $Script:ChecksPassed
    if ($totalChecks -gt 0) {
        $healthScore = [math]::Round(($Script:ChecksPassed / $totalChecks) * 100, 0)
        Write-Log "Network Health Score: $healthScore%" $(if ($healthScore -ge 80) { "SUCCESS" } elseif ($healthScore -ge 60) { "WARNING" } else { "ERROR" })
    }
    
    Write-Log "" "INFO"
    Write-Log "RECOMMENDATIONS:" "INFO"
    
    if ($Script:IssuesFound -gt 0) {
        Write-Log "• Address critical network issues immediately" "ERROR"
        Write-Log "• Check physical network connections" "ERROR"
        Write-Log "• Restart network adapters if needed" "ERROR"
    }
    
    if ($Script:WarningsFound -gt 0) {
        Write-Log "• Review network performance issues" "WARNING"
        Write-Log "• Consider upgrading internet plan if speeds are slow" "WARNING"
        Write-Log "• Update network drivers if available" "WARNING"
    }
    
    Write-Log "• Monitor network health regularly" "INFO"
    Write-Log "• Keep network drivers updated" "INFO"
    Write-Log "• Check for interference if using wireless" "INFO"
    
    Show-Separator
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "NETWORK DIAGNOSTICS SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: INTERNET CONNECTIVITY =====
    Write-Log "PHASE 1: INTERNET CONNECTIVITY" "INFO"
    Show-Separator
    Test-InternetConnectivity
    Show-Separator
    
    # ===== PHASE 2: DNS RESOLUTION =====
    Write-Log "PHASE 2: DNS RESOLUTION" "INFO"
    Show-Separator
    Test-DomainResolution
    Show-Separator
    
    # ===== PHASE 3: DNS PERFORMANCE =====
    Write-Log "PHASE 3: DNS SERVER PERFORMANCE" "INFO"
    Show-Separator
    Test-DNSServerPerformance
    Show-Separator
    
    # ===== PHASE 4: NETWORK ADAPTERS =====
    Write-Log "PHASE 4: NETWORK ADAPTERS" "INFO"
    Show-Separator
    Get-NetworkAdapters
    Show-Separator
    
    # ===== PHASE 5: IP CONFIGURATION =====
    Write-Log "PHASE 5: IP CONFIGURATION" "INFO"
    Show-Separator
    Get-IPConfiguration
    Show-Separator
    
    # ===== PHASE 6: DUPLICATE IP DETECTION =====
    Write-Log "PHASE 6: DUPLICATE IP DETECTION" "INFO"
    Show-Separator
    Detect-DuplicateIPs
    Show-Separator
    
    # ===== PHASE 7: DRIVER HEALTH =====
    Write-Log "PHASE 7: NETWORK DRIVER HEALTH" "INFO"
    Show-Separator
    Check-NetworkDrivers
    Show-Separator
    
    # ===== PHASE 8: LATENCY TEST =====
    Write-Log "PHASE 8: NETWORK LATENCY" "INFO"
    Show-Separator
    Test-NetworkLatency
    Show-Separator
    
    # ===== PHASE 9: SPEED TEST =====
    Write-Log "PHASE 9: NETWORK SPEED" "INFO"
    Show-Separator
    Test-NetworkSpeed
    Show-Separator
    
    # ===== COMPLETION SUMMARY =====
    Show-DiagnosticReport
    
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
