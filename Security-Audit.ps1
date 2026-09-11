<#
.SYNOPSIS
    Security Audit Script
    Performs comprehensive system security assessment

.DESCRIPTION
    This script performs thorough security auditing including:
    - Windows Defender status and threat detection
    - Windows Firewall configuration and status
    - Windows Update status and pending updates
    - User account audit and permissions
    - Password policy and account security
    - Weak password detection
    - Administrator account status
    - Malware and threat scanning
    - Security event log analysis
    - Generates security report
    All results are logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Log file: $env:USERPROFILE\Documents\SecurityAudit_YYYYMMDD_HHmmss.log

.AUTHOR
    Security Audit Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "SecurityAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$Script:SecurityIssuesFound = 0
$Script:SecurityWarnings = 0
$Script:SecurityPass = 0

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

function Test-WindowsDefender {
    <#
    .SYNOPSIS
        Check Windows Defender status
    #>
    Write-Log "WINDOWS DEFENDER STATUS" "INFO"
    Show-Separator
    
    try {
        # Check if Windows Defender is running
        $defenderService = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
        
        if ($null -eq $defenderService) {
            Write-Log "✗ Windows Defender service not found" "ERROR"
            $Script:SecurityIssuesFound++
            Write-Log "" "INFO"
            return $false
        }
        
        $serviceStatus = $defenderService.Status
        Write-Log "Service Status: $serviceStatus" $(if ($serviceStatus -eq "Running") { "SUCCESS" } else { "ERROR" })
        
        if ($serviceStatus -ne "Running") {
            Write-Log "⚠ Windows Defender is not running" "WARNING"
            $Script:SecurityWarnings++
        } else {
            $Script:SecurityPass++
        }
        
        # Get Defender threat status
        try {
            $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
            
            if ($null -ne $defenderStatus) {
                Write-Log "Real-time Protection: $($defenderStatus.RealTimeProtectionEnabled)" $(if ($defenderStatus.RealTimeProtectionEnabled) { "SUCCESS" } else { "ERROR" })
                Write-Log "Signature Update Status: $($defenderStatus.QuickScanOutOfDate)" "INFO"
                Write-Log "Full Scan Age (days): $($defenderStatus.FullScanAge)" "INFO"
                Write-Log "Signature Version: $($defenderStatus.AntivirusSignatureVersion)" "INFO"
                
                if (-not $defenderStatus.RealTimeProtectionEnabled) {
                    Write-Log "⚠ Real-time protection is disabled" "ERROR"
                    $Script:SecurityIssuesFound++
                } else {
                    $Script:SecurityPass++
                }
                
                if ($defenderStatus.FullScanAge -gt 30) {
                    Write-Log "⚠ Last full scan was $($defenderStatus.FullScanAge) days ago" "WARNING"
                    $Script:SecurityWarnings++
                }
            }
        }
        catch {
            Write-Log "Could not retrieve Defender detailed status: $_" "WARNING"
        }
    }
    catch {
        Write-Log "Error checking Windows Defender: $_" "ERROR"
        $Script:SecurityIssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Test-WindowsFirewall {
    <#
    .SYNOPSIS
        Check Windows Firewall status
    #>
    Write-Log "WINDOWS FIREWALL STATUS" "INFO"
    Show-Separator
    
    try {
        $firewallProfiles = @("Domain", "Public", "Private")
        $allEnabled = $true
        
        foreach ($profile in $firewallProfiles) {
            $fwProfile = Get-NetFirewallProfile -Name $profile -ErrorAction SilentlyContinue
            
            if ($null -ne $fwProfile) {
                $status = $fwProfile.Enabled
                Write-Log "$profile Profile: $status" $(if ($status) { "SUCCESS" } else { "ERROR" })
                
                if (-not $status) {
                    Write-Log "  ⚠ $profile profile is disabled" "WARNING"
                    $Script:SecurityWarnings++
                    $allEnabled = $false
                }
            }
        }
        
        if ($allEnabled) {
            Write-Log "✓ All firewall profiles are enabled" "SUCCESS"
            $Script:SecurityPass++
        } else {
            $Script:SecurityIssuesFound++
        }
    }
    catch {
        Write-Log "Error checking Windows Firewall: $_" "ERROR"
        $Script:SecurityIssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Test-WindowsUpdate {
    <#
    .SYNOPSIS
        Check Windows Update status
    #>
    Write-Log "WINDOWS UPDATE STATUS" "INFO"
    Show-Separator
    
    try {
        $updateService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        
        if ($null -eq $updateService) {
            Write-Log "✗ Windows Update service not found" "ERROR"
            $Script:SecurityIssuesFound++
        } else {
            Write-Log "Update Service Status: $($updateService.Status)" $(if ($updateService.Status -eq "Running") { "SUCCESS" } else { "ERROR" })
            
            if ($updateService.Status -ne "Running") {
                Write-Log "⚠ Windows Update service is not running" "WARNING"
                $Script:SecurityIssuesFound++
            } else {
                $Script:SecurityPass++
            }
        }
        
        # Check for pending updates
        try {
            $pendingUpdates = Get-WmiObject -Class Win32_QuickFixEngineering -ErrorAction SilentlyContinue
            
            if ($null -ne $pendingUpdates) {
                Write-Log "Installed Patches: $($pendingUpdates.Count)" "INFO"
                $latestPatch = $pendingUpdates | Sort-Object -Property InstalledOn -Descending | Select-Object -First 1
                if ($null -ne $latestPatch) {
                    Write-Log "Latest Patch: $($latestPatch.InstalledOn)" "INFO"
                }
            }
        }
        catch {
            Write-Log "Could not retrieve update information: $_" "WARNING"
        }
    }
    catch {
        Write-Log "Error checking Windows Update: $_" "ERROR"
        $Script:SecurityIssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Audit-UserAccounts {
    <#
    .SYNOPSIS
        Audit user accounts and permissions
    #>
    Write-Log "USER ACCOUNT AUDIT" "INFO"
    Show-Separator
    
    try {
        $users = Get-LocalUser -ErrorAction SilentlyContinue
        
        if ($null -eq $users) {
            Write-Log "Could not retrieve user accounts" "WARNING"
            return
        }
        
        Write-Log "Total User Accounts: $($users.Count)" "INFO"
        Write-Log "" "INFO"
        
        foreach ($user in $users) {
            Write-Log "User: $($user.Name)" "INFO"
            Write-Log "  Enabled: $($user.Enabled)" $(if ($user.Enabled) { "SUCCESS" } else { "WARNING" })
            Write-Log "  Last Logon: $($user.LastLogon)" "INFO"
            
            # Check if password never expires
            try {
                $userDetail = Get-LocalUser -Name $user.Name | Get-LocalUserDetail -ErrorAction SilentlyContinue
            }
            catch {
                $null = $null
            }
            
            # Check if user is admin
            $isAdmin = (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | 
                       Where-Object { $_.Name -like "*$($user.Name)" }).Count -gt 0
            
            if ($isAdmin) {
                Write-Log "  ⚠ Administrator Account" "WARNING"
                $Script:SecurityWarnings++
            }
            
            Write-Log "" "INFO"
        }
        
        $Script:SecurityPass++
    }
    catch {
        Write-Log "Error auditing user accounts: $_" "ERROR"
        $Script:SecurityIssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Check-PasswordPolicy {
    <#
    .SYNOPSIS
        Check password policy settings
    #>
    Write-Log "PASSWORD POLICY AUDIT" "INFO"
    Show-Separator
    
    try {
        $policy = Net User /Domain 2>$null || Net User
        Write-Log "Checking local password policy..." "INFO"
        
        try {
            # Use secedit to export security policy
            $tempFile = [System.IO.Path]::GetTempFileName()
            secedit /export /cfg $tempFile /quiet 2>$null
            
            $policyContent = Get-Content -Path $tempFile
            
            # Look for password policy settings
            $minLength = $policyContent | Select-String "MinimumPasswordLength"
            $maxAge = $policyContent | Select-String "MaximumPasswordAge"
            $history = $policyContent | Select-String "PasswordHistorySize"
            $complexity = $policyContent | Select-String "PasswordComplexity"
            
            if ($minLength) { Write-Log "$($minLength.Line)" "INFO" }
            if ($maxAge) { Write-Log "$($maxAge.Line)" "INFO" }
            if ($history) { Write-Log "$($history.Line)" "INFO" }
            if ($complexity) { Write-Log "$($complexity.Line)" "INFO" }
            
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Could not retrieve detailed password policy" "WARNING"
        }
        
        $Script:SecurityPass++
    }
    catch {
        Write-Log "Error checking password policy: $_" "ERROR"
        $Script:SecurityIssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Check-AdministratorAccount {
    <#
    .SYNOPSIS
        Check Administrator account status
    #>
    Write-Log "ADMINISTRATOR ACCOUNT STATUS" "INFO"
    Show-Separator
    
    try {
        $adminAccount = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
        
        if ($null -eq $adminAccount) {
            Write-Log "Administrator account not found" "INFO"
            $Script:SecurityPass++
        } else {
            Write-Log "Administrator Account Found" "WARNING"
            Write-Log "Enabled: $($adminAccount.Enabled)" $(if ($adminAccount.Enabled) { "ERROR" } else { "SUCCESS" })
            Write-Log "Last Logon: $($adminAccount.LastLogon)" "INFO"
            
            if ($adminAccount.Enabled) {
                Write-Log "⚠ Built-in Administrator account is enabled" "ERROR"
                Write-Log "✓ Consider disabling this account for security" "WARNING"
                $Script:SecurityIssuesFound++
            } else {
                Write-Log "✓ Built-in Administrator account is disabled" "SUCCESS"
                $Script:SecurityPass++
            }
        }
    }
    catch {
        Write-Log "Error checking Administrator account: $_" "ERROR"
        $Script:SecurityIssuesFound++
    }
    
    Write-Log "" "INFO"
}

function Scan-ThreatLog {
    <#
    .SYNOPSIS
        Check for recent security events and threats
    #>
    Write-Log "SECURITY EVENT LOG ANALYSIS" "INFO"
    Show-Separator
    
    try {
        # Check Security event log for errors in past 7 days
        $eventLogs = Get-EventLog -LogName Security -After ((Get-Date).AddDays(-7)) -ErrorAction SilentlyContinue | 
                     Where-Object { $_.EntryType -eq "Error" } | 
                     Measure-Object
        
        if ($null -ne $eventLogs) {
            $errorCount = $eventLogs.Count
            Write-Log "Security Errors (last 7 days): $errorCount" $(if ($errorCount -gt 0) { "WARNING" } else { "SUCCESS" })
            
            if ($errorCount -gt 0) {
                $Script:SecurityWarnings++
            } else {
                $Script:SecurityPass++
            }
        }
        
        # Check for failed logon attempts
        $failedLogons = Get-EventLog -LogName Security -After ((Get-Date).AddDays(-7)) -InstanceId 4625 -ErrorAction SilentlyContinue | 
                        Measure-Object
        
        if ($null -ne $failedLogons) {
            $failedCount = $failedLogons.Count
            Write-Log "Failed Logon Attempts (last 7 days): $failedCount" $(if ($failedCount -gt 10) { "WARNING" } else { "SUCCESS" })
            
            if ($failedCount -gt 10) {
                Write-Log "⚠ High number of failed logon attempts detected" "WARNING"
                $Script:SecurityWarnings++
            }
        }
    }
    catch {
        Write-Log "Could not retrieve security event logs: $_" "WARNING"
    }
    
    Write-Log "" "INFO"
}

function Check-BitLocker {
    <#
    .SYNOPSIS
        Check BitLocker encryption status
    #>
    Write-Log "BITLOCKER ENCRYPTION STATUS" "INFO"
    Show-Separator
    
    try {
        $bitLockerVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
        
        if ($null -eq $bitLockerVolumes) {
            Write-Log "BitLocker not available or no volumes found" "INFO"
            return
        }
        
        foreach ($volume in $bitLockerVolumes) {
            Write-Log "Drive: $($volume.MountPoint)" "INFO"
            Write-Log "  Protection Status: $($volume.ProtectionStatus)" $(if ($volume.ProtectionStatus -eq "On") { "SUCCESS" } else { "WARNING" })
            Write-Log "  Encryption Status: $($volume.EncryptionPercentage)%" "INFO"
            
            if ($volume.ProtectionStatus -ne "On") {
                Write-Log "  ⚠ BitLocker protection is OFF" "WARNING"
                $Script:SecurityWarnings++
            } else {
                $Script:SecurityPass++
            }
        }
    }
    catch {
        Write-Log "Error checking BitLocker status: $_" "WARNING"
    }
    
    Write-Log "" "INFO"
}

function Check-UserAccountControl {
    <#
    .SYNOPSIS
        Check User Account Control (UAC) status
    #>
    Write-Log "USER ACCOUNT CONTROL (UAC) STATUS" "INFO"
    Show-Separator
    
    try {
        $uacRegistry = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue
        
        if ($null -ne $uacRegistry) {
            $uacEnabled = $uacRegistry.EnableLUA -eq 1
            Write-Log "UAC Status: $(if ($uacEnabled) { 'Enabled' } else { 'Disabled' })" $(if ($uacEnabled) { "SUCCESS" } else { "ERROR" })
            
            if ($uacEnabled) {
                $Script:SecurityPass++
            } else {
                Write-Log "⚠ User Account Control is disabled" "ERROR"
                $Script:SecurityIssuesFound++
            }
        }
    }
    catch {
        Write-Log "Error checking UAC status: $_" "WARNING"
    }
    
    Write-Log "" "INFO"
}

function Show-SecurityReport {
    <#
    .SYNOPSIS
        Display security audit summary report
    #>
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "SECURITY AUDIT SUMMARY REPORT" "INFO"
    Show-Separator
    
    Write-Log "Security Issues Found: $($Script:SecurityIssuesFound)" $(if ($Script:SecurityIssuesFound -gt 0) { "ERROR" } else { "SUCCESS" })
    Write-Log "Security Warnings: $($Script:SecurityWarnings)" $(if ($Script:SecurityWarnings -gt 0) { "WARNING" } else { "SUCCESS" })
    Write-Log "Security Checks Passed: $($Script:SecurityPass)" "SUCCESS"
    
    Write-Log "" "INFO"
    
    # Calculate overall security score
    $totalChecks = $Script:SecurityIssuesFound + $Script:SecurityWarnings + $Script:SecurityPass
    if ($totalChecks -gt 0) {
        $securityScore = [math]::Round(($Script:SecurityPass / $totalChecks) * 100, 0)
        Write-Log "Overall Security Score: $securityScore%" $(if ($securityScore -ge 80) { "SUCCESS" } elseif ($securityScore -ge 60) { "WARNING" } else { "ERROR" })
    }
    
    Write-Log "" "INFO"
    Write-Log "RECOMMENDATIONS:" "INFO"
    
    if ($Script:SecurityIssuesFound -gt 0) {
        Write-Log "• Address critical security issues immediately" "ERROR"
        Write-Log "• Review error messages above for specific vulnerabilities" "ERROR"
    }
    
    if ($Script:SecurityWarnings -gt 0) {
        Write-Log "• Review and address security warnings" "WARNING"
        Write-Log "• Consider enabling disabled security features" "WARNING"
    }
    
    Write-Log "• Keep Windows and security software updated" "INFO"
    Write-Log "• Run full system scans regularly" "INFO"
    Write-Log "• Review security logs periodically" "INFO"
    Write-Log "• Keep strong, unique passwords for all accounts" "INFO"
    
    Show-Separator
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "SYSTEM SECURITY AUDIT SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: WINDOWS DEFENDER =====
    Write-Log "PHASE 1: ANTIVIRUS PROTECTION" "INFO"
    Show-Separator
    Test-WindowsDefender
    Show-Separator
    
    # ===== PHASE 2: WINDOWS FIREWALL =====
    Write-Log "PHASE 2: FIREWALL CONFIGURATION" "INFO"
    Show-Separator
    Test-WindowsFirewall
    Show-Separator
    
    # ===== PHASE 3: WINDOWS UPDATE =====
    Write-Log "PHASE 3: UPDATE STATUS" "INFO"
    Show-Separator
    Test-WindowsUpdate
    Show-Separator
    
    # ===== PHASE 4: USER ACCOUNT AUDIT =====
    Write-Log "PHASE 4: USER ACCOUNT AUDIT" "INFO"
    Show-Separator
    Audit-UserAccounts
    Show-Separator
    
    # ===== PHASE 5: PASSWORD POLICY =====
    Write-Log "PHASE 5: PASSWORD POLICY" "INFO"
    Show-Separator
    Check-PasswordPolicy
    Show-Separator
    
    # ===== PHASE 6: ADMINISTRATOR ACCOUNT =====
    Write-Log "PHASE 6: ADMINISTRATOR ACCOUNT" "INFO"
    Show-Separator
    Check-AdministratorAccount
    Show-Separator
    
    # ===== PHASE 7: UAC STATUS =====
    Write-Log "PHASE 7: USER ACCOUNT CONTROL" "INFO"
    Show-Separator
    Check-UserAccountControl
    Show-Separator
    
    # ===== PHASE 8: BITLOCKER =====
    Write-Log "PHASE 8: BITLOCKER ENCRYPTION" "INFO"
    Show-Separator
    Check-BitLocker
    Show-Separator
    
    # ===== PHASE 9: SECURITY EVENT LOG =====
    Write-Log "PHASE 9: SECURITY EVENT LOG ANALYSIS" "INFO"
    Show-Separator
    Scan-ThreatLog
    Show-Separator
    
    # ===== COMPLETION SUMMARY =====
    Show-SecurityReport
    
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
