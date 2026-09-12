<#
.SYNOPSIS
    Network Diagnostics Script

.DESCRIPTION
    Performs network connectivity, DNS, adapter, IP configuration,
    gateway, ARP, driver, latency, and download-speed tests.

.NOTES
    Recommended: Run PowerShell as Administrator.
    Log location: C:\temp\NetworkDiagnostics_YYYYMMDD_HHmmss.log
#>

#Requires -Version 5.1

# =========================
# CONFIGURATION
# =========================

$LogPath = "C:\temp"
$LogFileName = "NetworkDiagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName

$Script:IssuesFound = 0
$Script:WarningsFound = 0
$Script:ChecksPassed = 0

$InternetTestHost = "8.8.8.8"

$DNSServers = @(
    "8.8.8.8",       # Google DNS
    "1.1.1.1",       # Cloudflare DNS
    "208.67.222.222" # OpenDNS
)

# =========================
# LOGGING
# =========================

function Write-Log {
    param (
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

    try {
        Add-Content -Path $LogFile -Value $LogMessage -ErrorAction Stop
    }
    catch {
        Write-Host "Unable to write to log file: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}

function Show-Separator {
    Write-Log "================================================================" "INFO"
}

# =========================
# INTERNET CONNECTIVITY
# =========================

function Test-InternetConnectivity {
    Write-Log "INTERNET CONNECTIVITY TEST" "INFO"
    Show-Separator

    Write-Log "Testing connectivity to $InternetTestHost" "INFO"

    try {
        $PingResults = Test-Connection `
            -ComputerName $InternetTestHost `
            -Count 4 `
            -ErrorAction SilentlyContinue

        if ($null -ne $PingResults -and $PingResults.Count -gt 0) {
            Write-Log "Internet connectivity: SUCCESS" "SUCCESS"

            $ResponseTimes = @(
                $PingResults |
                    Where-Object { $_.ResponseTime -ne $null } |
                    Select-Object -ExpandProperty ResponseTime
            )

            if ($ResponseTimes.Count -gt 0) {
                $AverageLatency = [math]::Round(
                    ($ResponseTimes | Measure-Object -Average).Average,
                    2
                )

                $MinimumLatency = (
                    $ResponseTimes | Measure-Object -Minimum
                ).Minimum

                $MaximumLatency = (
                    $ResponseTimes | Measure-Object -Maximum
                ).Maximum

                $SuccessfulPings = $ResponseTimes.Count
                $PacketLoss = [math]::Round(
                    (1 - ($SuccessfulPings / 4)) * 100,
                    0
                )

                Write-Log "Average latency: $AverageLatency ms" "INFO"
                Write-Log "Minimum latency: $MinimumLatency ms" "INFO"
                Write-Log "Maximum latency: $MaximumLatency ms" "INFO"
                Write-Log "Packet loss: $PacketLoss%" "INFO"

                if ($PacketLoss -eq 0) {
                    Write-Log "No packet loss detected" "SUCCESS"
                }
                else {
                    Write-Log "Packet loss detected" "WARNING"
                    $Script:WarningsFound++
                }
            }

            $Script:ChecksPassed++
        }
        else {
            Write-Log "No internet connectivity detected" "ERROR"
            $Script:IssuesFound++
        }
    }
    catch {
        Write-Log "Connectivity test failed: $($_.Exception.Message)" "ERROR"
        $Script:IssuesFound++
    }

    Write-Log "" "INFO"
}

# =========================
# DNS DOMAIN RESOLUTION
# =========================

function Test-DomainResolution {
    Write-Log "DNS DOMAIN RESOLUTION TEST" "INFO"
    Show-Separator

    $TestDomains = @(
        "google.com",
        "microsoft.com",
        "github.com"
    )

    $ResolvedCount = 0

    foreach ($Domain in $TestDomains) {
        Write-Log "Resolving: $Domain" "INFO"

        try {
            $Results = Resolve-DnsName `
                -Name $Domain `
                -Type A `
                -ErrorAction Stop

            $IPv4Addresses = @(
                $Results |
                    Where-Object { $_.Type -eq "A" } |
                    Select-Object -ExpandProperty IPAddress
            )

            if ($IPv4Addresses.Count -gt 0) {
                Write-Log `
                    "Resolved to: $($IPv4Addresses -join ', ')" `
                    "SUCCESS"

                $ResolvedCount++
            }
            else {
                Write-Log "No IPv4 address returned" "ERROR"
                $Script:IssuesFound++
            }
        }
        catch {
            Write-Log `
                "Error resolving $Domain`: $($_.Exception.Message)" `
                "ERROR"

            $Script:IssuesFound++
        }
    }

    if ($ResolvedCount -eq $TestDomains.Count) {
        Write-Log "All domains resolved successfully" "SUCCESS"
        $Script:ChecksPassed++
    }
    else {
        Write-Log `
            "$($TestDomains.Count - $ResolvedCount) domain(s) failed to resolve" `
            "WARNING"

        $Script:WarningsFound++
    }

    Write-Log "" "INFO"
}

# =========================
# DNS SERVER PERFORMANCE
# =========================

function Test-DNSServerPerformance {
    Write-Log "DNS SERVER PERFORMANCE TEST" "INFO"
    Show-Separator

    $DnsTests = @(
        @{ Name = "Google DNS";     Address = "8.8.8.8" },
        @{ Name = "Cloudflare DNS"; Address = "1.1.1.1" },
        @{ Name = "OpenDNS";        Address = "208.67.222.222" }
    )

    foreach ($DnsTest in $DnsTests) {
        Write-Log `
            "Testing $($DnsTest.Name) ($($DnsTest.Address))" `
            "INFO"

        try {
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $Result = Resolve-DnsName `
                -Name "google.com" `
                -Server $DnsTest.Address `
                -Type A `
                -ErrorAction Stop

            $Stopwatch.Stop()

            $ResponseTime = [math]::Round(
                $Stopwatch.Elapsed.TotalMilliseconds,
                2
            )

            if ($null -ne $Result) {
                Write-Log "Response time: $ResponseTime ms" "SUCCESS"
                $Script:ChecksPassed++
            }
            else {
                Write-Log "No response from DNS server" "WARNING"
                $Script:WarningsFound++
            }
        }
        catch {
            Write-Log `
                "DNS test failed: $($_.Exception.Message)" `
                "WARNING"

            $Script:WarningsFound++
        }
    }

    Write-Log "" "INFO"
}

# =========================
# NETWORK ADAPTERS
# =========================

function Get-NetworkAdapters {
    Write-Log "NETWORK ADAPTER INFORMATION" "INFO"
    Show-Separator

    try {
        $Adapters = @(Get-NetAdapter -ErrorAction Stop)

        if ($Adapters.Count -eq 0) {
            Write-Log "No network adapters found" "ERROR"
            $Script:IssuesFound++
            return
        }

        Write-Log "Found $($Adapters.Count) network adapter(s)" "INFO"
        Write-Log "" "INFO"

        foreach ($Adapter in $Adapters) {
            Write-Log "Adapter: $($Adapter.Name)" "INFO"
            Write-Log `
                "Description: $($Adapter.InterfaceDescription)" `
                "INFO"

            if ($Adapter.Status -eq "Up") {
                Write-Log "Status: $($Adapter.Status)" "SUCCESS"
                $Script:ChecksPassed++
            }
            else {
                Write-Log "Status: $($Adapter.Status)" "WARNING"
                $Script:WarningsFound++
            }

            Write-Log "Media type: $($Adapter.MediaType)" "INFO"
            Write-Log "Link speed: $($Adapter.LinkSpeed)" "INFO"
            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log `
            "Error retrieving network adapters: $($_.Exception.Message)" `
            "ERROR"

        $Script:IssuesFound++
    }
}

# =========================
# IP CONFIGURATION
# =========================

function Get-IPConfiguration {
    Write-Log "IP CONFIGURATION AUDIT" "INFO"
    Show-Separator

    try {
        $Interfaces = @(
            Get-NetIPConfiguration -ErrorAction Stop |
                Where-Object { $null -ne $_.IPv4Address }
        )

        if ($Interfaces.Count -eq 0) {
            Write-Log "No IPv4 configuration found" "ERROR"
            $Script:IssuesFound++
            return
        }

        foreach ($Interface in $Interfaces) {
            $IPv4Address = $Interface.IPv4Address.IPAddress
            $PrefixLength = $Interface.IPv4Address.PrefixLength
            $Gateway = $Interface.IPv4DefaultGateway.NextHop

            Write-Log `
                "Interface: $($Interface.InterfaceAlias)" `
                "INFO"

            Write-Log "IPv4 address: $IPv4Address" "INFO"
            Write-Log "Prefix length: $PrefixLength" "INFO"

            if ([string]::IsNullOrWhiteSpace($Gateway)) {
                Write-Log "IPv4 gateway: Not configured" "WARNING"
                $Script:WarningsFound++
            }
            else {
                Write-Log "IPv4 gateway: $Gateway" "INFO"
            }

            $DnsConfig = Get-DnsClientServerAddress `
                -InterfaceIndex $Interface.InterfaceIndex `
                -AddressFamily IPv4 `
                -ErrorAction SilentlyContinue

            if ($null -ne $DnsConfig -and
                $DnsConfig.ServerAddresses.Count -gt 0) {

                Write-Log `
                    "DNS servers: $($DnsConfig.ServerAddresses -join ', ')" `
                    "INFO"
            }
            else {
                Write-Log "DNS servers: Not configured" "WARNING"
                $Script:WarningsFound++
            }

            $Script:ChecksPassed++
            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log `
            "Error retrieving IP configuration: $($_.Exception.Message)" `
            "ERROR"

        $Script:IssuesFound++
    }
}

# =========================
# GATEWAY TEST
# =========================

function Test-DefaultGateway {
    Write-Log "DEFAULT GATEWAY TEST" "INFO"
    Show-Separator

    try {
        $DefaultRoute = Get-NetRoute `
            -DestinationPrefix "0.0.0.0/0" `
            -AddressFamily IPv4 `
            -ErrorAction Stop |
            Sort-Object RouteMetric |
            Select-Object -First 1

        if ($null -eq $DefaultRoute) {
            Write-Log "No default gateway found" "ERROR"
            $Script:IssuesFound++
            return
        }

        $Gateway = $DefaultRoute.NextHop
        Write-Log "Default gateway: $Gateway" "INFO"

        $PingResult = Test-Connection `
            -ComputerName $Gateway `
            -Count 4 `
            -ErrorAction SilentlyContinue

        if ($null -ne $PingResult -and $PingResult.Count -gt 0) {
            Write-Log "Default gateway is reachable" "SUCCESS"
            $Script:ChecksPassed++
        }
        else {
            Write-Log "Default gateway is not reachable" "ERROR"
            $Script:IssuesFound++
        }
    }
    catch {
        Write-Log `
            "Gateway test failed: $($_.Exception.Message)" `
            "ERROR"

        $Script:IssuesFound++
    }

    Write-Log "" "INFO"
}

# =========================
# ARP / DUPLICATE IP CHECK
# =========================

function Detect-DuplicateIPs {
    Write-Log "DUPLICATE IP ADDRESS DETECTION" "INFO"
    Show-Separator

    try {
        Write-Log "Refreshing the ARP cache..." "INFO"

        $null = arp.exe -d "*" 2>$null

        $DefaultRoute = Get-NetRoute `
            -DestinationPrefix "0.0.0.0/0" `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric |
            Select-Object -First 1

        if ($null -eq $DefaultRoute) {
            Write-Log "Could not determine the default gateway" "WARNING"
            $Script:WarningsFound++
            return
        }

        $Gateway = $DefaultRoute.NextHop
        Write-Log "Gateway: $Gateway" "INFO"

        $null = Test-Connection `
            -ComputerName $Gateway `
            -Count 1 `
            -ErrorAction SilentlyContinue

        $ArpLines = @(
            arp.exe -a 2>$null |
                Select-String "dynamic"
        )

        if ($ArpLines.Count -eq 0) {
            Write-Log "No dynamic ARP entries found" "WARNING"
            $Script:WarningsFound++
            return
        }

        $IpAddresses = @(
            $ArpLines |
                ForEach-Object {
                    $Parts = $_.Line -split "\s+"

                    foreach ($Part in $Parts) {
                        if ($Part -match `
                            "^\d{1,3}(\.\d{1,3}){3}$") {
                            $Part
                        }
                    }
                }
        )

        $DuplicateAddresses = @(
            $IpAddresses |
                Group-Object |
                Where-Object { $_.Count -gt 1 }
        )

        Write-Log `
            "Dynamic ARP entries found: $($ArpLines.Count)" `
            "INFO"

        if ($DuplicateAddresses.Count -eq 0) {
            Write-Log "No duplicate IP addresses detected" "SUCCESS"
            $Script:ChecksPassed++
        }
        else {
            foreach ($Duplicate in $DuplicateAddresses) {
                Write-Log `
                    "Possible duplicate IP: $($Duplicate.Name)" `
                    "WARNING"
            }

            $Script:WarningsFound++
        }
    }
    catch {
        Write-Log `
            "Duplicate IP scan failed: $($_.Exception.Message)" `
            "WARNING"

        $Script:WarningsFound++
    }

    Write-Log "" "INFO"
}

# =========================
# DRIVER HEALTH
# =========================

function Test-NetworkDrivers {
    Write-Log "NETWORK DRIVER HEALTH CHECK" "INFO"
    Show-Separator

    try {
        $Adapters = @(
            Get-CimInstance `
                -ClassName Win32_NetworkAdapter `
                -ErrorAction Stop |
                Where-Object { $_.PhysicalAdapter -eq $true }
        )

        if ($Adapters.Count -eq 0) {
            Write-Log "No physical network adapters found" "WARNING"
            $Script:WarningsFound++
            return
        }

        foreach ($Adapter in $Adapters) {
            Write-Log "Adapter: $($Adapter.Name)" "INFO"
            Write-Log "Manufacturer: $($Adapter.Manufacturer)" "INFO"
            Write-Log "Driver status: $($Adapter.Status)" "INFO"

            if ($Adapter.Status -eq "OK") {
                Write-Log "Driver status is healthy" "SUCCESS"
                $Script:ChecksPassed++
            }
            else {
                Write-Log "Possible driver issue detected" "WARNING"
                $Script:WarningsFound++
            }

            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log `
            "Driver check failed: $($_.Exception.Message)" `
            "ERROR"

        $Script:IssuesFound++
    }
}

# =========================
# LATENCY TEST
# =========================

function Test-NetworkLatency {
    Write-Log "NETWORK LATENCY TEST" "INFO"
    Show-Separator

    $TestHosts = @(
        @{ Name = "Google DNS";     Host = "8.8.8.8" },
        @{ Name = "Cloudflare DNS"; Host = "1.1.1.1" },
        @{ Name = "Quad9 DNS";      Host = "9.9.9.9" }
    )

    foreach ($TestHost in $TestHosts) {
        Write-Log `
            "Testing $($TestHost.Name) ($($TestHost.Host))" `
            "INFO"

        try {
            $PingResults = Test-Connection `
                -ComputerName $TestHost.Host `
                -Count 4 `
                -ErrorAction SilentlyContinue

            if ($null -ne $PingResults -and $PingResults.Count -gt 0) {
                $ResponseTimes = @(
                    $PingResults |
                        Where-Object { $_.ResponseTime -ne $null } |
                        Select-Object -ExpandProperty ResponseTime
                )

                $AverageLatency = [math]::Round(
                    ($ResponseTimes | Measure-Object -Average).Average,
                    2
                )

                Write-Log `
                    "Average latency: $AverageLatency ms" `
                    "SUCCESS"

                if ($AverageLatency -lt 50) {
                    Write-Log "Excellent latency" "SUCCESS"
                }
                elseif ($AverageLatency -lt 100) {
                    Write-Log "Good latency" "SUCCESS"
                }
                else {
                    Write-Log "High latency detected" "WARNING"
                    $Script:WarningsFound++
                }

                $Script:ChecksPassed++
            }
            else {
                Write-Log "No response received" "ERROR"
                $Script:IssuesFound++
            }
        }
        catch {
            Write-Log `
                "Latency test failed: $($_.Exception.Message)" `
                "WARNING"

            $Script:WarningsFound++
        }
    }

    Write-Log "" "INFO"
}

# =========================
# DOWNLOAD SPEED TEST
# =========================

function Test-NetworkSpeed {
    Write-Log "NETWORK SPEED ESTIMATION" "INFO"
    Show-Separator

    Write-Log "Downloading a test file..." "INFO"

    $TestUrl = "https://speed.hetzner.de/100MB.bin"
    $TempFile = Join-Path $env:TEMP "NetworkSpeedTest_$(Get-Random).bin"

    try {
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        Invoke-WebRequest `
            -Uri $TestUrl `
            -OutFile $TempFile `
            -UseBasicParsing `
            -ErrorAction Stop

        $Stopwatch.Stop()

        $FileInfo = Get-Item $TempFile
        $FileSizeBytes = $FileInfo.Length
        $DurationSeconds = $Stopwatch.Elapsed.TotalSeconds

        if ($DurationSeconds -le 0) {
            throw "The download duration was invalid."
        }

        $SpeedMbps = [math]::Round(
            (($FileSizeBytes * 8) / $DurationSeconds) / 1MB,
            2
        )

        Write-Log "Downloaded: $FileSizeBytes bytes" "INFO"
        Write-Log "Duration: $DurationSeconds seconds" "INFO"
        Write-Log "Estimated speed: $SpeedMbps Mbps" "SUCCESS"

        if ($SpeedMbps -ge 100) {
            Write-Log "Excellent download speed" "SUCCESS"
        }
        elseif ($SpeedMbps -ge 25) {
            Write-Log "Good download speed" "SUCCESS"
        }
        else {
            Write-Log "Slow download speed detected" "WARNING"
            $Script:WarningsFound++
        }

        $Script:ChecksPassed++
    }
    catch {
        Write-Log `
            "Could not perform speed test: $($_.Exception.Message)" `
            "WARNING"

        $Script:WarningsFound++
    }
    finally {
        if (Test-Path $TempFile) {
            Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Log "" "INFO"
}

# =========================
# DIAGNOSTIC REPORT
# =========================

function Show-DiagnosticReport {
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "NETWORK DIAGNOSTIC SUMMARY REPORT" "INFO"
    Show-Separator

    if ($Script:IssuesFound -gt 0) {
        Write-Log `
            "Issues found: $($Script:IssuesFound)" `
            "ERROR"
    }
    else {
        Write-Log `
            "Issues found: $($Script:IssuesFound)" `
            "SUCCESS"
    }

    if ($Script:WarningsFound -gt 0) {
        Write-Log `
            "Warnings found: $($Script:WarningsFound)" `
            "WARNING"
    }
    else {
        Write-Log `
            "Warnings found: $($Script:WarningsFound)" `
            "SUCCESS"
    }

    Write-Log `
        "Checks passed: $($Script:ChecksPassed)" `
        "SUCCESS"

    $TotalChecks = `
        $Script:IssuesFound +
        $Script:WarningsFound +
        $Script:ChecksPassed

    if ($TotalChecks -gt 0) {
        $HealthScore = [math]::Round(
            ($Script:ChecksPassed / $TotalChecks) * 100,
            0
        )

        if ($HealthScore -ge 80) {
            $HealthLevel = "SUCCESS"
        }
        elseif ($HealthScore -ge 60) {
            $HealthLevel = "WARNING"
        }
        else {
            $HealthLevel = "ERROR"
        }

        Write-Log `
            "Network health score: $HealthScore%" `
            $HealthLevel
    }

    Write-Log "" "INFO"
    Write-Log "RECOMMENDATIONS:" "INFO"

    if ($Script:IssuesFound -gt 0) {
        Write-Log "Review the errors listed above." "ERROR"
        Write-Log "Check physical network connections." "ERROR"
        Write-Log "Restart the network adapter if necessary." "ERROR"
    }

    if ($Script:WarningsFound -gt 0) {
        Write-Log "Review latency and speed results." "WARNING"
        Write-Log "Check for outdated network drivers." "WARNING"
        Write-Log "Check wireless signal strength and interference." "WARNING"
    }

    Write-Log "Run this diagnostic periodically." "INFO"
    Show-Separator
}

# =========================
# MAIN
# =========================

function Main {
    try {
        if (-not (Test-Path -Path $LogPath)) {
            New-Item `
                -ItemType Directory `
                -Path $LogPath `
                -Force `
                -ErrorAction Stop |
                Out-Null
        }

        # Create the file before the first log entry.
        New-Item `
            -ItemType File `
            -Path $LogFile `
            -Force `
            -ErrorAction Stop |
            Out-Null

        Write-Log "NETWORK DIAGNOSTICS SCRIPT" "INFO"
        Write-Log `
            "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            "INFO"

        Write-Log "Log file: $LogFile" "INFO"
        Show-Separator

        Write-Log "PHASE 1: INTERNET CONNECTIVITY" "INFO"
        Show-Separator
        Test-InternetConnectivity

        Write-Log "PHASE 2: DNS RESOLUTION" "INFO"
        Show-Separator
        Test-DomainResolution

        Write-Log "PHASE 3: DNS SERVER PERFORMANCE" "INFO"
        Show-Separator
        Test-DNSServerPerformance

        Write-Log "PHASE 4: NETWORK ADAPTERS" "INFO"
        Show-Separator
        Get-NetworkAdapters

        Write-Log "PHASE 5: IP CONFIGURATION" "INFO"
        Show-Separator
        Get-IPConfiguration

        Write-Log "PHASE 6: DEFAULT GATEWAY" "INFO"
        Show-Separator
        Test-DefaultGateway

        Write-Log "PHASE 7: DUPLICATE IP DETECTION" "INFO"
        Show-Separator
        Detect-DuplicateIPs

        Write-Log "PHASE 8: NETWORK DRIVER HEALTH" "INFO"
        Show-Separator
        Test-NetworkDrivers

        Write-Log "PHASE 9: NETWORK LATENCY" "INFO"
        Show-Separator
        Test-NetworkLatency

        Write-Log "PHASE 10: NETWORK SPEED" "INFO"
        Show-Separator
        Test-NetworkSpeed

        Show-DiagnosticReport

        Write-Log `
            "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            "INFO"

        Write-Log "Log file saved to: $LogFile" "SUCCESS"
        Show-Separator

        Write-Host ""
        Write-Host "Diagnostics completed." -ForegroundColor Cyan
        Write-Host "Log file: $LogFile" -ForegroundColor Cyan
    }
    catch {
        Write-Host `
            "The script could not complete: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}

Main
